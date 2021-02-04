import CLwIP

public struct IP4Network {
    var prefix: UInt8
    public let baseAddress: IP4Address
    public let netmask: IP4Address

    /// Create an IPv4 Network by specifying the base address from the network and the prefix. This initializer will
    /// crash if the address is not a valid base address for the network.
    /// - Parameters:
    ///   - prefix: The prefix for example /24 for a network with netmast 255.255.255.0
    ///   - address: The base address of the network
    public init(prefix: UInt8, baseAddress: IP4Address) {
        precondition(prefix <= 32)

        let netmask = IP4Address(addr: ip4_addr(addr: (UInt32(0xff_ff_ff_ff) << (32-prefix)).bigEndian))

        precondition((baseAddress & netmask) == baseAddress)

        self.netmask = netmask
        self.prefix = prefix
        self.baseAddress = baseAddress
    }
    
    /// Create an IPv4 Network by specifying _any_ address from the network and the prefix
    /// - Parameters:
    ///   - prefix: The prefix for example /24 for a network with netmast 255.255.255.0
    ///   - address: Any address of the network
    public init(prefix: UInt8, address: IP4Address) {
        let netmask = IP4Address(addr: ip4_addr(addr: (UInt32(0xff_ff_ff_ff) << (32-prefix)).bigEndian))
        let baseAddress = address & netmask
        
        self.init(prefix: prefix, baseAddress: baseAddress)
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

    /// Create an IP Address from a string. 192.168.0.1 can be represented by `IP4Address("192.168.0.1")`
    public init?(_ string: String) {
        let inner = string.withCString {
            ipaddr_addr($0)
        }

        guard inner != IPADDR_NONE.bigEndian else {
            return nil
        }

        self.address = ip4_addr(addr: inner)
    }
    
    
    /// Create an IP Address by components. 192.168.0.1 can be represented by `IP4Address(192,168,0,1)`
    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        self.address = ip4_addr(addr: ((
                                        UInt32(a) << 24 +
                                        UInt32(b) << 16 +
                                        UInt32(c) << 8 +
                                        UInt32(d))
        ).bigEndian)
    }

    public func next(in network: IP4Network) -> IP4Address? {
        let addr = UInt32(bigEndian: address.addr)
        guard addr < .max else { return nil }
        let nextAddr = IP4Address(addr: ip4_addr_t(addr: (addr + 1).bigEndian))

        guard network.contains(address: nextAddr) else { return nil }

        return nextAddr
    }
}

extension IP4Address: CustomStringConvertible {
    public var description: String { self.string }
}

public extension UInt32 {
    init(_ ip4: IP4Address) {
        self.init(bigEndian: ip4.address.addr)
    }
}
