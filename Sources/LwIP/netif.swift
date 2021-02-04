//
//  File.swift
//  
//
//  Created by Matthias Bartelmeß on 18.10.20.
//

import Foundation
import CLwIP

/// A (virtual) Network Interface
public class NetworkInterface: CallbackQueueProtocol {
    var callbackQueue: CallbackQueue = CallbackQueue()

    static var interfaceNumber = 0

    var inner: UnsafeMutablePointer<netif>
    let output: (Data) -> Void
    let ready : ((_ interface: NetworkInterface) -> Void)?
    let mtu: UInt16

    var address: IP4Address { IP4Address(addr: inner.pointee.ip_addr ) }
    var netmask: IP4Address { IP4Address(addr: inner.pointee.netmask ) }
    var gateway: IP4Address { IP4Address(addr: inner.pointee.gw ) }

    /// Create a new Network Interface
    /// - Parameters:
    ///   - address: IPv4 address of the interface
    ///   - netmask: IPv4 netmask of the interface
    ///   - gateway: IPv4 gateway of the interface
    ///   - mtu: maximum transmission unit
    ///   - output: function that writes packets to a packet stream
    ///   - ready: will be called once the interface is ready
    public init(address: IP4Address,
                netmask: IP4Address,
                gateway: IP4Address,
                mtu: UInt16 = 1500,
                output: @escaping (Data) -> Void,
                ready: ((_ interface: NetworkInterface) -> Void)? = nil) {

        var addr = address
        var mask = netmask
        var gateway = gateway

        self.inner = UnsafeMutablePointer<netif>.allocate(capacity: 1)
        self.output = output
        self.mtu = mtu
        self.ready = ready

        let initFunc : @convention(c) (UnsafeMutablePointer<netif>?) -> err_t = {interface in
            guard let interface = interface else {
                return ERR_ARG
            }

            let networkInterface = NetworkInterface.from(netif: interface)
            networkInterface?.initialize(interface: interface)
            return ERR_OK
        }

        initializeTCPIP()

        tcpip {
            guard netif_add(inner,
                            &addr.address,
                            &mask.address,
                            &gateway.address,
                            Unmanaged<NetworkInterface>.passUnretained(self).toOpaque(),
                            initFunc,
                            tcpip_input) != nil else {
                abort()
            }

            netif_set_up(inner)
        }

    }

    static func from(netif: UnsafePointer<netif>) -> NetworkInterface? {
        if let state = netif.pointee.state {
            return Unmanaged<NetworkInterface>.fromOpaque(state).takeUnretainedValue()
        }

        return nil
    }

    let outputFunc : @convention(c) (
        UnsafeMutablePointer<netif>?,
        UnsafeMutablePointer<pbuf>?,
        UnsafePointer<ip_addr_t>?) -> err_t = { interface, buffer, address in

        guard let buffer = buffer, let interface = interface, let address = address else {
            return ERR_ARG
        }

        let netif = NetworkInterface.from(netif: interface)
        let data = Data(buffer)

        netif?.callback {
            netif?.output(data)
        }

        return ERR_OK
    }

    private func initialize(interface: UnsafeMutablePointer<netif>) {
        interface.pointee.output = outputFunc
        interface.pointee.mtu = mtu

        let interfaceNumber = NetworkInterface.interfaceNumber
        NetworkInterface.interfaceNumber += 1

        interface.pointee.name = (Int8(Character("e").asciiValue!),
                                  Int8(Character("0").asciiValue!) + Int8(UInt32(interfaceNumber) % 20))
        netif_set_link_up(interface)
        callback {
            self.ready?(self)
        }
    }
    
    /// Start dispatching events of the network interface and set the queue to deliver the events on.
    /// - Parameter queue: The queue to dispatch the events on
    public func start(queue: DispatchQueue) {
        self.callbackQueue.start(queue: queue)
    }

    /// Pass a packet to the network interface
    public func input(packet: Data) throws {
        try packet.withPbuf { (buf) -> Void in
            pbuf_ref(buf)
            try inner.pointee.input(buf, inner).throw()
        }
    }

    private func remove0() {
        self.inner.pointee.state = nil
        netif_remove(inner)
    }

    /// Remove the interface
    public func remove() {
        tcpip {
            remove0()
        }
    }

    deinit {
        self.remove()
        inner.deallocate()
    }
}
