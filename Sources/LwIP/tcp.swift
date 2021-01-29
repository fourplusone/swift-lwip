//
//  File.swift
//  
//
//  Created by Matthias Bartelmeß on 22.10.20.
//

import CLwIP
import Foundation

/// Abstract base class for connections and listeners
public class TCPBase: CallbackQueueProtocol {

    public enum State: Equatable {
        case setup
        case preparing
        case ready
        case failed(LwIPError)
        case cancelled
    }

    public var state: State = .setup {
        willSet {
            assertCoreLocked()
        }
        didSet {
            if oldValue != state {
                callback { [self] in stateUpdateHandler?(state) }
            }
        }
    }

    /// Handler that will be called on state changes
    public var stateUpdateHandler: ((State) -> Void)?

    /// Associated LwIP PCB
    fileprivate var tcpPcb: UnsafeMutablePointer<tcp_pcb>?

    /// A TCP connection retains itself until closed to avoid deadlocks
    var retainedUntilClosed: Unmanaged<TCPBase>?

    var callbackQueue: CallbackQueue = CallbackQueue()

    /// Callback for LwIP for `tcp_err`
    static private var errorFunction: tcp_err_fn = { arg, err -> Void in
        guard let arg = arg else { return }
        let tcp = Unmanaged<TCPBase>.fromOpaque(arg).takeUnretainedValue()
        tcp.tcpPcb = nil

        let error = LwIPError(rawValue: Int(err.rawValue))!
        tcp.state = .failed(error)

        tcp.release0()

    }

    init() {
        tcpip {
            let pcb = tcp_new()

            guard pcb != nil else {
                self.state = .failed(.outOfMemory)
                return
            }

            tcpPcb = pcb
            setup()
        }
    }

    /// Initialize with an exisiting pcb
    /// - Parameter pcb: an
    init(pcb: UnsafeMutablePointer<tcp_pcb>) {
        assertCoreLocked()
        self.tcpPcb = pcb
        setup()
    }

    /// Setup the connection/listener.
    func setup() {
        assertCoreLocked()

        guard let pcb = tcpPcb else {
            preconditionFailure("pcb cannot be nil")
        }
        tcp_arg(pcb, Unmanaged.passUnretained(self).toOpaque())
        tcp_err(pcb, TCPBase.errorFunction)

        if pcb.pointee.state == ESTABLISHED {
            state = .ready
        }

        retainedUntilClosed = Unmanaged.passRetained(self)
    }

    private func bind0(address: IP4Address, port: UInt16) throws {
        guard tcpPcb != nil else { return }
        try withUnsafePointer(to: address.address) { address in
            tcp_bind(tcpPcb, address, port)
        }.throw()
    }

    /// Bind to connection/listener to a address & port.
    /// - Parameters:
    ///   - address: IP Address to bind to
    ///   - port: Port to bind to
    /// - Throws: LwIP Error
    func bind(address: IP4Address, port: UInt16) throws {
        try tcpip {
            try bind0(address: address, port: port)
        }
    }

    private func bind0(interface: NetworkInterface) {
        guard tcpPcb != nil else { return }
        withUnsafePointer(to: interface.inner) { netif in
            tcp_bind_netif(self.tcpPcb, netif)
        }
    }

    /// Bind to connection/listener to a network interface. All packets sent/received are guaranteed to have
    /// come in via the specified `NetworkInterface`, and all outgoing packets will go out via the specified `NetworkInterface`.
    /// - Parameters:
    ///   - address: IP Address to bind to
    ///   - port: Port to bind to
    /// - Throws: LwIP Error
    func bind(interface: NetworkInterface) {
        tcpip {
            bind0(interface: interface)
        }
    }

    private func close0() {
        assertCoreLocked()
        if let inner = tcpPcb {
            self.tcpPcb = nil
            tcp_arg(inner, nil)
            try! tcp_close(inner).throw()
            state = .cancelled
        }
    }

    /// Closes the connection
    public func close() {
        tcpip {
            release0()
            close0()
        }
    }

    func release0() {
        assertCoreLocked()
        if let retained = retainedUntilClosed {
            retainedUntilClosed = nil
            callback {
                retained.release()
            }
        }

    }

    deinit {
        precondition(tcpPcb == nil, "Open Connections may not be deallocated")
    }
}

/// Listener for TCP Connections
public final class TCPListener: TCPBase {

    /// Create a new Listener
    /// - Parameters:
    ///   - address: The address to bind to
    ///   - port: The port to bind to
    /// - Throws: LwIP Error
    public init(address: IP4Address, port: UInt16) throws {
        super.init()
        try bind(address: address, port: port)
    }

    /// Callback for LwIP for `tcp_accept`
    static private var acceptFunction: tcp_accept_fn = { arg, pcb, err -> err_t in
        guard let arg = arg else { return ERR_ARG }
        let tcp = Unmanaged<TCPListener>.fromOpaque(arg).takeUnretainedValue()
        
        guard err == ERR_OK else {
            return err
        }

        guard let pcb = pcb else {
            return ERR_ARG
        }

        tcp_backlog_delayed(pcb)
        let connection = TCPConnection(pcb: pcb)

        tcp.callback {
            tcp.acceptHandler?(connection)
        }

        return ERR_OK
    }

    /// This handler will be called once a new connection has been accepted. The handler is responsible to
    /// set up the connection object properly and to call `start(queue:)`
    public var acceptHandler: ((TCPConnection) -> Void)?

    private func listen0(backlog: UInt8) throws {
        guard tcpPcb != nil else { return }

        var err: err_t = ERR_OK
        tcpPcb = tcp_listen_with_backlog_and_err(tcpPcb, backlog, &err)
        try err.throw()

        tcp_accept(tcpPcb, TCPListener.acceptFunction)
    }

    /// Listen for connections
    /// - Parameter backlog: The maximum number of connections which have not been accepted
    /// - Throws: LwIP Error
    public func listen(backlog: UInt8) throws {
        try tcpip {
            try listen0(backlog: backlog)
            state = .ready
        }
    }
    
    /// Start dispatching events of the connection/listener and set the queue to deliver the events on.
    /// - Parameter queue: The queue to dispatch the events on
    public func start(queue: DispatchQueue) {
        self.callbackQueue.start(queue: queue)
    }

}

/// A TCP Connection
public final class TCPConnection: TCPBase {
    /// Create a new connection on a network interface
    /// - Parameter interface:
    public init(interface: NetworkInterface) {
        super.init()
        try! bind(address: interface.address, port: 0)
    }

    /// Create a connection with an existing pcb
    /// - Parameter pcb:
    override init(pcb: UnsafeMutablePointer<tcp_pcb>) {
        assertCoreLocked()
        super.init(pcb: pcb)
    }

    override func setup() {
        tcp_recv(tcpPcb, TCPConnection.recvFunction)
        tcp_sent(tcpPcb, TCPConnection.sentFunction)
        super.setup()
    }

    /// Callback for LwIP for `tcp_connect`
    static private var connectedFunction: tcp_connected_fn = { arg, _, _ -> err_t in
        guard let arg = arg else { return ERR_ARG }

        let tcp = Unmanaged<TCPConnection>.fromOpaque(arg).takeUnretainedValue()

        tcp.state = .ready

        return ERR_OK
    }

    /// Callback for LwIP for `tcp_recv`
    static private var recvFunction: tcp_recv_fn = { arg, _, pbuf, _ -> err_t in
        guard let arg = arg else { return ERR_ARG }

        let tcp = Unmanaged<TCPConnection>.fromOpaque(arg).takeUnretainedValue()

        guard let pbuf = pbuf else {
            // Connection was closed
            tcp_arg(tcp.tcpPcb, nil)
            tcp.tcpPcb = nil
            tcp.state = .cancelled

            tcp.release0()

            return ERR_OK
        }
        defer { pbuf_free(pbuf) }

        guard tcp.state == .ready else {
            return ERR_OK

        }

        let data = Data(pbuf)

        tcp.callback {
            if let recvHandler = tcp.recvHandler {
                recvHandler(data, {
                    tcpip { tcp.recved0(len: UInt16(data.count)) }
                })
            } else {
                tcpip {
                    tcp.recved0(len: UInt16(data.count))
                }
                
            }
        }

        return ERR_OK
    }

    /// This handler is called once new data is available. Once the data has been processed by the application
    /// `completionHandler()` must be called to request more data
    public var recvHandler : ((_ data: Data, _ completionHandler: @escaping () -> Void) -> Void)?

    /// Whether the connection should be closed once all scheduled data has been processed
    private var closeGracefully = false

    /// Callback for LwIP for `tcp_sent`
    static private var sentFunction: tcp_sent_fn = { arg, _, len -> err_t in
        guard let arg = arg else { return ERR_ARG }

        let tcp = Unmanaged<TCPConnection>.fromOpaque(arg).takeUnretainedValue()
        tcp.sendQueue -= UInt64(len)
        tcp.writePendingData0()

        if tcp.sendQueue == 0 && tcp.closeGracefully {
            tcp.callback {
                tcp.forceClose()
            }
        }

        return ERR_OK
    }

    /// This handler will be called once more data can be processed by the TCPIP stack
    private var writeCompletionHandler : (() -> Void)?

    /// Number of unacknowledged bytes
    private var sendQueue: UInt64 = 0

    /// Start dispatching events of the connection/listener and set the queue to deliver the events on.
    /// - Parameter queue: The queue to dispatch the events on
    public func start(queue: DispatchQueue) {
        tcpip {
            if let pcb = tcpPcb {
                tcp_backlog_accepted(pcb)
            }
            callbackQueue.start0(queue: queue)
        }
    }

    private func connect0(address: IP4Address, port: UInt16) throws {
        guard tcpPcb != nil else { return }

        try withUnsafePointer(to: address.address) { address  in
            tcp_connect(tcpPcb, address, port, TCPConnection.connectedFunction)
        }.throw()
    }

    /// Open a connection
    /// - Parameters:
    ///   - address: Destination address
    ///   - port: Destination Port
    /// - Throws: LwIP error
    public func connect(address: IP4Address, port: UInt16) throws {
        try tcpip {
            state = .preparing
            try connect0(address: address, port: port)
        }
    }

    private func output0() throws {
        guard tcpPcb != nil else { return }

        try tcp_output(tcpPcb).throw()
    }

    private func recved0(len: UInt16) {
        if let inner = tcpPcb {
            tcp_recved(inner, len)
        }
    }

    func forceClose() {
        super.close()
    }

    /// Close the connection
    override public func close() {
        let shouldCloseGracefully = tcpip { () -> Bool in
            if sendQueue > 0 {
                closeGracefully = true
                return true
            }
            return false
        }

        if !shouldCloseGracefully {
            forceClose()
        }
    }

    /// Data that has not been processed by the tcpip stack yet
    var pendingData: [UInt8] = []

    /// Forward pending data to the tcp ip stack.
    private func writePendingData0() {

        guard let pcb = tcpPcb else { return }
        let sendBuffer = pcb.pointee.snd_buf
        guard sendBuffer > 0 else { return }

        let sendSize = min(Int(sendBuffer), pendingData.count)
        let toSend = pendingData[0 ..< sendSize]

        let result = toSend.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> err_t in
            tcp_write(tcpPcb, pointer.baseAddress, u16_t(pointer.count), u8_t(TCP_WRITE_FLAG_COPY))
        }

        if let error = result.error {
            self.state = .failed(error)
            self.forceClose()
        } else {
            self.pendingData[0...] = pendingData[sendSize...]
        }

        do {
            try output0()
        } catch let error as LwIPError {
            self.state = .failed(error)
            self.forceClose()
        } catch {  }

        // More data can be handled by the TCP Stack
        if pendingData.count == 0 && sendBuffer > 0 {
            if let handler = writeCompletionHandler {
                writeCompletionHandler = nil
                callback {
                    handler()
                }
            }

        }
    }

    private func write0(data: Data, completion:@escaping () -> Void) throws {
        precondition(writeCompletionHandler == nil)
        guard tcpPcb != nil else { return }

        sendQueue += UInt64(data.count)
        pendingData = [UInt8](data)
        writeCompletionHandler = completion
        writePendingData0()
    }

    /// Send new data
    /// - Parameters:
    ///   - data:
    ///   - completion: This hanlder will be called once more data can be processed by the stack
    /// - Throws: LwIP error
    public func write(data: Data, completion: @escaping () -> Void) throws {
        try tcpip {
            try write0(data: data, completion: completion)
        }
    }
}
