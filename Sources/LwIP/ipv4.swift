import CLwIP

public struct IP4Network {
    var prefix: UInt8
    public let baseAddress: IP4Address
    public let netmask: IP4Address

    public init(prefix: UInt8, baseAddress: IP4Address) {
        precondition(prefix <= 32)

        let netmask = IP4Address(addr: ip4_addr(addr: (UInt32(0xff_ff_ff_ff) << (32-prefix)).bigEndian))

        precondition((baseAddress & netmask) == baseAddress)

        self.netmask = netmask
        self.prefix = prefix
        self.baseAddress = baseAddress
    }

    public func contains(address: IP4Address) -> Bool {
        return (address & netmask) == (baseAddress & netmask)
    }
}

public struct IP4Address: Hashable {
    public static func & (lhs: IP4Address, rhs: IP4Address) -> IP4Address {
        return IP4Address(addr: ip4_addr(addr: lhs.address.addr & rhs.address.addr))
    }

    public static func == (lhs: IP4Address, rhs: IP4Address) -> Bool {
        return lhs.address.addr == rhs.address.addr
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(address.addr)
    }

    var address: ip4_addr_t

    public var string: String {
        var inner = self.address
        let buf = UnsafeMutableBufferPointer<Int8>.allocate(capacity: 16)
        defer { buf.deallocate() }

        let strBuffer = ip4addr_ntoa_r(&inner, buf.baseAddress, Int32(buf.count))!
        return String(cString: strBuffer)
    }

    init(addr: ip4_addr_t) {
        self.address = addr
    }

    public init?(_ string: String) {
        let inner = string.withCString {
            ipaddr_addr($0)
        }

        guard inner != IPADDR_NONE.bigEndian else {
            return nil
        }

        self.address = ip4_addr(addr: inner)
    }

    public func next(in network: IP4Network) -> IP4Address? {
        let addr = UInt32(bigEndian: address.addr)
        guard addr < .max else { return nil }
        let nextAddr = IP4Address(addr: ip4_addr_t(addr: (addr + 1).bigEndian))

        guard network.contains(address: nextAddr) else { return nil }

        return nextAddr
    }
}

public extension UInt32 {
    init(_ ip4: IP4Address) {
        self.init(bigEndian: ip4.address.addr)
    }
}
