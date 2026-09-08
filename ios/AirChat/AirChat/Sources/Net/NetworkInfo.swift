//
//  NetworkInfo.swift
//  AirChat
//
//  Equivalent of Android's MainActivity.getSmartIpAddress().
//  On iOS we cannot read the SSID (that needs the paid/approved
//  "Access Wi-Fi Information" entitlement), but getifaddrs() is always
//  available, which is enough: we only need the IPv4 the phone owns.
//

import Foundation
import Darwin

enum InterfaceKind: String {
    case hotspot      // iPhone is the access point (Personal Hotspot ON)
    case wifi         // iPhone is a client on someone else's Wi-Fi
    case cellular     // pdp_ip0 — reachable only by the carrier, useless for LAN clients
    case other
}

struct InterfaceAddress: Hashable {
    let name: String
    let ip: String
    let netmask: String?
    var kind: InterfaceKind {
        if name == "lo0" { return .other }
        if name.hasPrefix("bridge") || name == "en6" || name == "en7" || name == "ap1" || name.contains("swlan") { return .hotspot }
        if name == "en0" || name == "en1" || name == "en2" { return .wifi }
        if name.hasPrefix("pdp_ip") { return .cellular }
        return .other
    }
}

enum NetworkInfo {

    /// All IPv4 addresses currently bound by the device, loopback excluded.
    static func ipv4Addresses() -> [InterfaceAddress] {
        var result: [InterfaceAddress] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            defer { cursor = p.pointee.ifa_next }
            guard let addr = p.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: p.pointee.ifa_name)
            if name == "lo0" { continue }

            // Standard idiom: rebound the raw sockaddr to sockaddr_in, then hand
            // &sin_addr (an in_addr) to inet_ntop.
            var sockaddrCopy = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &sockaddrCopy.sin_addr, &buffer, socklen_t(buffer.count)) != nil else { continue }
            let ip = String(cString: buffer)
            if ip.isEmpty || ip.hasPrefix("127.") { continue }

            var mask: String? = nil
            if let netmask = p.pointee.ifa_netmask, netmask.pointee.sa_family == UInt8(AF_INET) {
                var maskCopy = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var maskBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &maskCopy.sin_addr, &maskBuffer, socklen_t(maskBuffer.count)) != nil {
                    mask = String(cString: maskBuffer)
                }
            }
            result.append(InterfaceAddress(name: name, ip: ip, netmask: mask))
        }
        return result
    }

    static var all: [InterfaceAddress] { ipv4Addresses() }

    /// Hotspot wins over Wi-Fi wins over cellular: clients can only reach us on the
    /// interface they are actually attached to.
    static func bestHostAddress() -> InterfaceAddress? {
        let addrs = ipv4Addresses()
        return addrs.first { $0.kind == .hotspot }
            ?? addrs.first { $0.kind == .wifi }
            ?? addrs.first { $0.kind == .other }
            ?? addrs.first { $0.kind == .cellular }
    }

    /// True while Personal Hotspot is up. iOS gives no API to *enable* it (there is
    /// no public tethering API at any entitlement level), so the UI uses this only to
    /// nag the user into turning it on in Settings.
    static var isPersonalHotspotUp: Bool {
        ipv4Addresses().contains { $0.kind == .hotspot }
    }

    static var hasReachableLAN: Bool {
        let a = bestHostAddress()
        return a != nil && a?.kind != .cellular
    }

    static func describe() -> String {
        let addrs = ipv4Addresses()
        if addrs.isEmpty { return "no IPv4 interface" }
        return addrs.map { "\($0.name) \($0.ip) (\($0.kind.rawValue))" }.joined(separator: "\n")
    }
}
