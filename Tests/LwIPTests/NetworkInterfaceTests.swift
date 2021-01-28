import XCTest
@testable import LwIP

final class NetworkInterfaceTests: XCTestCase {

    let ip1 = IP4Address("192.168.0.2")!
    let ip2 = IP4Address("192.168.0.3")!
    let netmask = IP4Address("255.255.255.0")!
    let gateway = IP4Address("192.168.0.1")!
    
    let queue = DispatchQueue(label: "Queue1")
    let queue2 = DispatchQueue(label: "Queue2")
    let queue3 = DispatchQueue(label: "Queue3")
    
    func testMany() {
        for _ in 0 ..< 100 {

            print("-----------------------------------------------------------------------------")

            testBasic()
        }
    }
    
    }
    
    func testBasic() {


        let sema = DispatchSemaphore(value: 0)
        let closeSema = DispatchSemaphore(value: 0)


        let testData = "HelloWorld".data(using: .utf8)!
        let testPort: UInt16 = 8080

        let gatewayInterface = NetworkInterface(address: gateway, netmask: netmask, gateway: gateway) { _ in
        } ready: { _ in

        }

        let interface1 = NetworkInterface(address: ip1,
                                          netmask: netmask,
                                          gateway: gateway) { data in
            try! gatewayInterface.input(packet: data)
        } ready: { _ in

        }

        let interface2 = NetworkInterface(address: ip2,
                                          netmask: netmask,
                                          gateway: gateway) { data in
            try! gatewayInterface.input(packet: data)
        } ready: { _ in

        }
        gatewayInterface.start(queue: queue)
        interface1.start(queue: queue)
        interface2.start(queue: queue)

        let connection = TCPConnection(interface: interface1)
        let listener = try! TCPListener(address: ip2, port: testPort)

        var received = Data()

        listener.acceptHandler = { connection in
            print("acceped")
            connection.recvHandler = { [weak connection] data, completionHandler in
                received.append(data)
                print("Count \(received.count)")
                assert(received.count == 0 || received.count == 10)
                if received.count == 10 {
                    sema.signal()
                    connection?.forceClose()
                }
                completionHandler()
            }
            connection.start(queue: self.queue)

        }

        listener.bind(interface: interface2)
        try! listener.listen(backlog: 10)

        connection.stateUpdateHandler = { [weak connection] state in
            print(state)
            switch state {
            case .ready:
                try! connection?.write(data: testData) {
                    print("Data sent")
                    connection?.close()
                }
            case .cancelled:
                closeSema.signal()
            case .failed(let err):
                print("Connection Error:", err)
                closeSema.signal()

            case .setup: break
            case .preparing: break
            }
        }

        try! connection.connect(address: ip2, port: testPort)

        listener.start(queue: queue2)
        connection.start(queue: queue3)

        sema.wait()
        closeSema.wait()
        connection.close()
        listener.close()
        interface1.remove()
        interface2.remove()
        gatewayInterface.remove()
    }
}
