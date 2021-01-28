import Foundation
import CLwIP

extension Data {
    private func pbuf() -> UnsafeMutablePointer<pbuf> {
        guard let buf = pbuf_alloc(PBUF_RAW, u16_t(self.count), PBUF_RAM) else {
            abort()
        }

        guard self.withUnsafeBytes({ (buffer: UnsafeRawBufferPointer) -> err_t in
            pbuf_take(buf, buffer.baseAddress, u16_t(self.count))
        }) == ERR_OK else { abort() }

        return buf
    }

    func withPbuf<T>(_ body: (UnsafeMutablePointer<pbuf>) throws -> T) rethrows -> T {
        let buf = pbuf()
        defer { pbuf_free(buf) }

        return try body(buf)
    }

    init(_ buf: UnsafeMutablePointer<pbuf>) {
        if buf.pointee.next == nil,
            (buf.pointee.type_internal & UInt8(PBUF_TYPE_FLAG_DATA_VOLATILE)) == 0 {
            pbuf_ref(buf)

            self.init(bytesNoCopy: buf.pointee.payload,
                      count: Int(buf.pointee.len),
                      deallocator: .custom({ _, _ in
                        pbuf_free(buf)
                      }))
        } else {
            let buffer = malloc(Int(buf.pointee.tot_len))!
            let count = pbuf_copy_partial(buf, buffer, buf.pointee.tot_len, 0)

            self.init(bytesNoCopy: buffer, count: Int(count), deallocator: .free)
        }
    }
}
