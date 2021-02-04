import CLwIP
import Foundation

/// UDP Socket.
public class UDP: CallbackQueueProtocol {
    private var udpPcb: UnsafeMutablePointer<udp_pcb>?

    var callbackQueue: CallbackQueue = CallbackQueue()

    public typealias RecvHandler = (_ data: Data, _ ip: IP4Address, _ port: UInt16) -> Void
    
    /// This handler will be called, once a new packet arrives.
    public var recvHandler: RecvHandler?

    static private var recvFunction: udp_recv_fn = { arg, _, pbuf, addr, port in
        let udp = Unmanaged<UDP>
            .fromOpaque(arg!)
            .takeUnretainedValue()

        let ipaddr = IP4Address(addr: addr!.pointee)
        let data = Data(pbuf!)
        pbuf_free(pbuf)

        udp.callback {
            udp.recvHandler?(data, ipaddr, port)
        }

    }

    public init(recvHandler: RecvHandler?) {
        tcpip {
            udpPcb = udp_new()!

            if let recvHandler = recvHandler {
                self.recvHandler = recvHandler
            }

            udp_recv(udpPcb,
                     UDP.recvFunction,
                     Unmanaged.passUnretained(self).toOpaque())
        }
    }
    
    /// Start dispatching events of the connection/listener and set the queue to deliver the events on.
    /// - Parameter queue: The queue to dispatch the events on
    public func start(queue: DispatchQueue) {
        self.callbackQueue.start(queue: queue)
    }

    private func bind0(address: IP4Address, port: UInt16) throws {
        try withUnsafePointer(to: address.address) { address in
            udp_bind(udpPcb, address, port)
        }.throw()
    }

    public func bind(address: IP4Address, port: UInt16) throws {
        try tcpip {
            try bind0(address: address, port: port)
        }
    }

    private func bind0(interface: NetworkInterface) {
        udp_bind_netif(udpPcb, interface.inner)
    }
    
    /// Bind this socket to a network interface. All packets received via this socket
    /// are guaranteed to have come in via the specified `NetworkInterface`, and all
    /// outgoing packets will go out via the specified `NetworkInterface`
    /// - Parameter interface: The network interface to bind to
    public func bind(interface: NetworkInterface) {
        tcpip {
            bind0(interface: interface)
        }
    }

    private func disconnect0() {
        udp_disconnect(udpPcb)
    }

    /// Remove the socket.
    public func disconnect() {
        tcpip {
            udp_disconnect(udpPcb)
        }
    }

    private func send0(data: Data) throws {
        try tcpip {
            try data.withPbuf { buffer in
                udp_send(udpPcb, buffer)
            }.throw()
        }
    }

    /// Send a datagram to the current remote ip
    public func send(data: Data) throws {
        try tcpip {
            try send0(data: data)
        }
    }

    private func send0(data: Data, address: IP4Address, port: UInt16 ) throws {
        data.withPbuf {
            var address = address.address
            udp_sendto(udpPcb, $0, &address, port)
        }
    }

    /// Send a datagram to a remote address
    public func send(data: Data, address: IP4Address, port: UInt16 ) throws {
        try tcpip {
            try send0(data: data, address: address, port: port)
        }
    }

    deinit {
        tcpip {
            udp_remove(udpPcb)
        }
    }
}
