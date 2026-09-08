//
//  MeshManager.swift
//  AirChat
//
//  iOS replacement for the Google Nearby Connections API used by MeshManager.kt.
//  Nearby Connections is a Play-Services framework and does not exist on iOS, and
//  there is no third-party equivalent that both stays entitlement-free and works
//  on a stock device. MultipeerConnectivity is the platform's own answer: it rides
//  on Bluetooth LE for discovery and AWDL (peer-to-peer Wi-Fi) for the data
//  channel, needs no infrastructure, and works in airplane mode with Wi-Fi on.
//
//  Same contract as the Android manager:
//    * advertise + browse on one service id
//    * AES-256-GCM payloads, IV||ct||tag
//    * dedupe on the message id, then relay to the other peers (range extension)
//

import Foundation
import MultipeerConnectivity
import CryptoKit
import UIKit

extension MCPeerID {
    /// Local identity string for a peer.
    ///
    /// Not `hashValue.description`: that is only consistent with `isEqual`, and two
    /// phones can legitimately show the same display name ("AirChat-Tom"). Not
    /// `ObjectIdentifier` either: Multipeer hands out fresh MCPeerID objects for the
    /// same peer across callbacks. MCPeerID is NSSecureCoding, so its archived bytes
    /// are a canonical form — hash those and both problems go away.
    var airchatID: String {
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true) {
            return SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        }
        return String(displayName.prefix(6)).data(using: .utf8).map {
            SHA256.hash(data: $0).prefix(6).map { String(format: "%02x", $0) }.joined()
        } ?? "peer"
    }
}

struct MeshPeer: Equatable, Hashable {
    let id: String          // MCPeerID hash representation
    let displayName: String
    var isConnected: Bool
}

protocol MeshManagerDelegate: AnyObject {
    func meshManager(_ manager: MeshManager, didReceiveJSON json: String)
    func meshManager(_ manager: MeshManager, didFindPeer peer: MeshPeer)
    func meshManager(_ manager: MeshManager, didLosePeer peer: MeshPeer)
    func meshManager(_ manager: MeshManager, didChangeConnectedPeers peers: [MeshPeer])
    func meshManager(_ manager: MeshManager, didFailWith message: String)
}

final class MeshManager: NSObject {

    /// MCServiceType must be 1...15 chars of [a-zA-Z0-9-]. This maps to the
    /// Bonjour name `_airchat-mesh._tcp` that Info.plist declares.
    static let serviceType = "airchat-mesh"

    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let session: MCSession
    private let myPeerID: MCPeerID
    private let roomKey: SymmetricKey?

    weak var delegate: MeshManagerDelegate?

    /// Multipeer invokes the session delegate on its own queue while the browser and
    /// advertiser callbacks land on the main queue; every field below is touched from
    /// both, hence one lock for all of them.
    private let stateLock = NSLock()
    private var discovered: [String: MeshPeer] = [:]
    private var seenMessageIds: [String] = []
    private var seenLookup: Set<String> = []
    private let maxSeenIds = 512
    private let maxPayloadBytes = 500 * 1024

    private(set) var isRunning = false
    var connectedPeers: [MeshPeer] {
        session.connectedPeers.map { MeshPeer(id: $0.airchatID,
                                               displayName: $0.displayName,
                                               isConnected: true) }
    }
    var pendingInvites: [MeshPeer] {
        stateLock.lock(); defer { stateLock.unlock() }
        return Array(discovered.values)
    }
    var nodeName: String { myPeerID.displayName }

    init(roomKeyBase64URL: String) {
        let name = ("AirChat-" + (UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name))
            .prefix(30)
        myPeerID = MCPeerID(displayName: String(name))
        session = MCSession(peer: myPeerID, displayName: nil) { config in
            // AirChat does its own AES-GCM on top, so no MC encryption layer.
            config.encryptionRequired = false
        }
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil,
                                              serviceType: MeshManager.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: MeshManager.serviceType)
        roomKey = AirChatCrypto.key(fromBase64URL: roomKeyBase64URL)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        advertiser.startAdvertising()
        browser.startBrowsingForPeers()
        NSLog("AirChat: mesh started as '\(nodeName)'")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        advertiser.stopAdvertising()
        browser.stopBrowsingForPeers()
        session.disconnect()
        stateLock.lock()
        discovered.removeAll()
        seenLookup.removeAll()
        seenMessageIds.removeAll()
        allBrowsedPeers.removeAll()
        stateLock.unlock()
        MeshPeerRegistry.shared.clear()
    }

    func connect(to peer: MeshPeer) {
        let known = MeshPeerRegistry.shared.peer(for: peer.id)
        stateLock.lock()
        let fallback = allBrowsedPeers.first { $0.displayName == peer.displayName }
        stateLock.unlock()
        guard let mcPeer = known ?? fallback else {
            delegate?.meshManager(self, didFailWith: "That peer is no longer nearby.")
            return
        }
        browser.invitePeer(mcPeer, to: session, withContext: nil, timeout: 20)
    }

    func disconnect(from peer: MeshPeer) {
        if let mc = session.connectedPeers.first(where: { $0.airchatID == peer.id }) {
            session.removePeer(mc)
        }
    }

    private var allBrowsedPeers: [MCPeerID] = []

    /// Send a chat frame to every connected peer. Frames larger than the MC data
    /// limit are dropped (the browser/WS path still delivers them locally).
    func send(json: String) {
        guard let key = roomKey else { return }
        guard !session.connectedPeers.isEmpty else { return }
        guard let raw = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              var object = raw as? [String: Any] else { return }
        if object["id"] == nil { object["id"] = UUID().uuidString }
        let id = object["id"] as? String ?? ""
        // Record our own id up front: with more than one peer, a relayed copy of our
        // own frame can come back to us and would otherwise print twice.
        stateLock.lock(); rememberLocked(id); stateLock.unlock()

        guard let serialised = try? JSONSerialization.data(withJSONObject: object, options: []),
              let payload = AirChatCrypto.seal(serialised, key: key) else { return }
        guard payload.count <= maxPayloadBytes else {
            NSLog("AirChat: mesh payload too big (\(payload.count) bytes), skipped")
            return
        }
        try? session.send(payload, toPeers: session.connectedPeers, with: .reliable)
    }

    /// Caller must hold `stateLock` (or be about to take it via `isFresh`).
    private func rememberLocked(_ id: String) {
        guard !id.isEmpty, !seenLookup.contains(id) else { return }
        seenLookup.insert(id)
        seenMessageIds.append(id)
        if seenMessageIds.count > maxSeenIds {
            let drop = seenMessageIds.removeFirst()
            seenLookup.remove(drop)
        }
    }

    /// True when this message id has not been handled yet. Mesh frames must be
    /// deduped across every inbound path, otherwise a two-hop relay loops.
    private func isFresh(_ id: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        if id.isEmpty { return true }
        if seenLookup.contains(id) { return false }
        rememberLocked(id)
        return true
    }

    private func handleIncoming(_ data: Data, from peer: MCPeerID) {
        guard let key = roomKey,
              let plain = AirChatCrypto.open(data, key: key),
              let text = String(data: plain, encoding: .utf8) else { return }   // wrong room key
        guard let raw = try? JSONSerialization.jsonObject(with: plain),
              let object = raw as? [String: Any] else { return }
        let id = object["id"] as? String ?? ""
        guard isFresh(id) else { return }
        delegate?.meshManager(self, didReceiveJSON: text)

        // Relay unchanged (still encrypted with the same room key) to everyone else.
        let others = session.connectedPeers.filter { $0.hashValue != peer.hashValue }
        if !others.isEmpty { try? session.send(data, toPeers: others, with: .reliable) }
    }
}

/// Weak-ish side table mapping the string ids we surface in UI back to MCPeerIDs.
/// Side table mapping the string ids we surface in UI back to MCPeerIDs. Multipeer
/// calls delegates on its own queues, so the table is guarded.
final class MeshPeerRegistry {
    static let shared = MeshPeerRegistry()
    private var table: [String: MCPeerID] = [:]
    private let lock = NSLock()

    func register(_ peer: MCPeerID) {
        lock.lock(); table[peer.airchatID] = peer; lock.unlock()
    }
    func peer(for id: String) -> MCPeerID? {
        lock.lock(); defer { lock.unlock() }; return table[id]
    }
    func clear() { lock.lock(); table.removeAll(); lock.unlock() }
}

// MARK: - MCSessionDelegate

extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        MeshPeerRegistry.shared.register(peerID)
        let peer = MeshPeer(id: peerID.airchatID,
                            displayName: peerID.displayName,
                            isConnected: state == .connected)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch state {
            case .connected:
                self.stateLock.lock()
                self.discovered.removeValue(forKey: peerID.airchatID)
                self.stateLock.unlock()
                self.delegate?.meshManager(self, didChangeConnectedPeers: self.connectedPeers)
            case .notConnected:
                self.delegate?.meshManager(self, didLosePeer: peer)
                self.delegate?.meshManager(self, didChangeConnectedPeers: self.connectedPeers)
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleIncoming(data, from: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser / browser

extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        MeshPeerRegistry.shared.register(peerID)
        // Auto-accept inside a room that already shares the symmetric key: a bad key
        // simply decrypts to garbage and is dropped in handleIncoming.
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.meshManager(self, didFailWith: "Mesh advertising failed: \(error.localizedDescription)")
        }
    }
}

extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        MeshPeerRegistry.shared.register(peerID)
        let peer = MeshPeer(id: peerID.airchatID, displayName: peerID.displayName, isConnected: false)
        stateLock.lock()
        allBrowsedPeers.append(peerID)
        discovered[peer.id] = peer
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.meshManager(self, didFindPeer: peer)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        stateLock.lock()
        let id = peerID.airchatID
        discovered.removeValue(forKey: id)
        allBrowsedPeers.removeAll { $0.airchatID == peerID.airchatID }
        stateLock.unlock()
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.meshManager(self, didFailWith: "Mesh discovery failed: \(error.localizedDescription)")
        }
    }
}
