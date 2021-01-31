import XCTest
@testable import LwIP

final class IP4Tests: XCTestCase {
    func testInitializers() {
        XCTAssertEqual(IP4Address("192.168.0.1"),
                       IP4Address(192,168,0,1))
    }
    
    func testNetwork(){
        let ip = IP4Address(192,168,0,1)
        let network = IP4Network(prefix: 24, address: ip)
        XCTAssertEqual(network.baseAddress, IP4Address(192,168,0,0))
        XCTAssertEqual(network.netmask, IP4Address(255,255,255,0))
        XCTAssertEqual(ip.next(in: network), IP4Address(192,168,0,2))
    }
}
