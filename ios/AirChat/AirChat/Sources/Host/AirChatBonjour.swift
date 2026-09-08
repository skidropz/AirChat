//
//  AirChatBonjour.swift
//  AirChat
//
//  iOS-side replacement for "a friend's phone shows up and asks to connect".
//
//  Android leans on Google Nearby Connections for both the mesh and for noticing a
//  neighbouring host. On iOS the equivalent of "there is an AirChat room right here"
//  is Bonjour/mDNS via Network.framework's NetService, which costs no entitlement
//  and no developer account. We publish the HTTP port + the 4-character join code and
//  browse for the same, so an iPhone can host and an iPhone (or Mac) can join by
//  tapping, without typing an IP.
//

import Foundation
import Network

struct DiscoveredRoom: Hashable {
    var id: String { "\(host):\(port)" }
    let name: String
    let host: String
    let port: UInt16
    let code: String
    var isAirChatiOS: Bool

    var joinURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        // No code (e.g. an Android host that publishes no TXT record) still works:
        // the server redirects "/" to the room page with the key in the fragment.
        components.path = code.isEmpty ? "/" : "/" + code
        return components.url
    }
}

final class AirChatBonjour: NSObject {

    static let serviceType = "_airchat-http._tcp"
    static let domain = "local."

    private var publisher: NetService?
    private var browser: NetServiceBrowser?
    private var resolving: Set<ObjectIdentifier> = []
    private var rooms: [String: DiscoveredRoom] = [:]

    var onRoomsChanged: (([DiscoveredRoom]) -> Void)?

    private(set) var discovered: [DiscoveredRoom] = []

    // MARK: Publishing (host role)

    func publish(code: String, port: UInt16) {
        stopPublishing()
        let name = UIDevice.current.name.isEmpty ? "AirChat" : "\(UIDevice.current.name) AirChat"
        let service = NetService(domain: AirChatBonjour.domain, type: AirChatBonjour.serviceType,
                                name: name, port: Int(port))
        // One TXT record, "k=v;k=v": browsers need the code to fetch the room key,
        // which the server only ever hands out through the URL fragment.
        let txt = "v=1;code=\(code);platform=iOS"
        service.setPropertyData([Data(txt.utf8)], forTXTRecordType: AirChatBonjour.domain)
        service.delegate = self
        service.publish()
        publisher = service
        NSLog("AirChat: bonjour publishing :\(port) code=\(code)")
    }

    func stopPublishing() {
        publisher?.stop()
        publisher?.delegate = nil
        publisher = nil
    }

    // MARK: Browsing (client role)

    func startBrowsing() {
        guard browser == nil else { return }
        let b = NetServiceBrowser()
        b.delegate = self
        b.includesPeerToPeer = true               // see hotspot-linked peers too
        b.searchForServices(ofType: AirChatBonjour.serviceType, inDomain: AirChatBonjour.domain)
        browser = b
    }

    func stopBrowsing() {
        browser?.stop()
        browser?.delegate = nil
        browser = nil
        rooms.removeAll()
        discovered = []
        onRoomsChanged?(discovered)
    }
}

extension AirChatBonjour: NetServiceDelegate {
    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        NSLog("AirChat: bonjour publish failed \(errorDict)")
    }

    func netServiceDidPublish(_ sender: NetService) {
        NSLog("AirChat: bonjour published as \(sender.name)")
    }

    func netServiceDidStop(_ sender: NetService) {}
}

extension AirChatBonjour: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !resolving.contains(ObjectIdentifier(service)) else { return }
        resolving.insert(ObjectIdentifier(service))
        service.delegate = self
        service.resolve(withTimeout: 8)
        _ = moreComing
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        if rooms.removeValue(forKey: service.name) != nil { refresh() }
        _ = moreComing
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        resolving.remove(ObjectIdentifier(sender))
        guard sender.port > 0 else { return }
        // Prefer the literal IPv4 the service answered with over the .local hostname:
        // on a Personal Hotspot the mDNS resolver is not always reachable for guests.
        let host = AirChatBonjour.ipv4(from: sender.addresses) ?? sender.hostName
        guard let host = host else { return }
        let txt = readCode(from: sender)
        let room = DiscoveredRoom(name: sender.name.isEmpty ? host : sender.name,
                                  host: host,
                                  port: UInt16(truncatingIfNeeded: sender.port),
                                  code: txt.code,
                                  isAirChatiOS: txt.platform == "iOS")
        rooms[sender.name] = room
        refresh()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.remove(ObjectIdentifier(sender))
    }

    /// The short code is published in a TXT record; the room key never is (it only
    /// travels in the URL fragment, exactly like the Android host behaves).
    private func readCode(from service: NetService) -> (code: String, platform: String) {
        var candidates: [Data] = []
        if let single = service.textRecordData { candidates.append(single) }
        if let many = service.getPropertyData(forTXTRecordType: AirChatBonjour.domain) { candidates.append(contentsOf: many) }
        var code = ""
        var platform = ""
        for data in candidates {
            guard let string = String(data: data, encoding: .utf8) else { continue }
            for pair in string.split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
                guard kv.count == 2 else { continue }
                let key = String(kv[0]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(kv[1]).trimmingCharacters(in: .whitespaces)
                if key == "code", value.count == 4 { code = value.uppercased() }
                if key == "platform" { platform = value }
            }
        }
        // Android hosts have no TXT code, so fall back to the documented default port path.
        if code.isEmpty { code = "" }
        return (code, platform)
    }

    static func ipv4(from addresses: [Data]?) -> String? {
        guard let addresses = addresses else { return nil }
        for data in addresses {
            let host = data.withUnsafeBytes { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                let sock = base.assumingMemoryBound(to: sockaddr.self)
                guard sock.pointee.sa_family == UInt8(AF_INET) else { return nil }
                var copy = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &copy.sin_addr, &buffer, socklen_t(buffer.count)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let host = host { return host }
        }
        return nil
    }

    private func refresh() {
        let list = rooms.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        discovered = list
        DispatchQueue.main.async { [weak self] in
            self?.onRoomsChanged?(list)
        }
    }
}
