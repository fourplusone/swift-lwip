import CLwIP
import Foundation


/// Hook for manally specifying a route from `src` to `dest`
/// This will only be called when no interface can be found based on the IP Address
public var ip4RouteHook : ((_ src: IP4Address, _ dest:IP4Address)->NetworkInterface?)? = nil

public enum IP4InputHookResult: Int32 {
    /// The packet has been ignored
    case ignored = 0
    /// The packet has been consumed and will not be processed further
    case consumed
}

/// Hook for processing packets of
public var ip4InputHook : ((Data, NetworkInterface)->IP4InputHookResult)? = nil

func initializeHooks() {
    assertCoreLocked()
    lwip_set_hook_ip4_route_src { (src, dest) -> UnsafeMutablePointer<netif>? in
        guard let src = src?.pointee else { return nil }
        guard let dest = dest?.pointee else { return nil }
        let interface = ip4RouteHook?(IP4Address(addr: src), IP4Address(addr: dest))
        return interface?.inner
    }
    
    lwip_set_hook_ip4_input { (packet, netif) -> Int32 in
        guard let packet = packet else { return 0 }
        guard let netif = netif, let interface = NetworkInterface.from(netif: netif) else {
            return 0
        }
        
        let result = ip4InputHook?(Data(packet), interface) ?? .ignored
        
        if result == .consumed {
            pbuf_free(packet)
        }
        return result.rawValue
    }
}
