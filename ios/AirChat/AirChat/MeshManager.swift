//
//  MeshManager.swift
//  AirChat
//
//  Hybrid mesh networking for iOS, the MultipeerConnectivity counterpart of Android's
//  Google Nearby Connections (P2P_CLUSTER). Phones discover each other over BLE, connect
//  over peer-to-peer Wi-Fi and pass the same AES-GCM envelope Android uses, so the two
//  platforms can form one mesh. A payload is re-broadcast to every other peer exactly once
//  (deduped by message id), which is what makes the range extension work.
//

import Foundation
import MultipeerConnectivity
import CryptoKit

final class MeshManager: NSObject {

    typealias MessageHandler = (String) -> Void
    typealias DeviceLostHandler = () -> Void
    typealias PeerFoundHandler = (String, String) -> Void // (peerID, displayName)

    private let myPeerID: MCPeerID
    private let roomKey: SymmetricKey
    private let onMessage: MessageHandler
    private let onDeviceLost: DeviceLostHandler
    private let onPeerFound: PeerFoundHandler

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private let serviceType = "airchat-mesh"
    private var seenMessageIDs = Set<String>()
    private var discoveredPeers: [String: MCPeerID] = [:]
    private var connectedPeers = Set<String>()

    init(name: String, base64RoomKey: String,
         onMessage: @escaping MessageHandler,
         onDeviceLost: @escaping DeviceLostHandler,
         onPeerFound: @escaping PeerFoundHandler) {
        self.myPeerID = MCPeerID(displayName: name)
        // Same 32-byte key the web layer uses; decoded URL-safe, matching Android.
        if let keyData = Self.decodeBase64URLSafe(base64RoomKey) {
            self.roomKey = SymmetricKey(data: keyData)
        } else {
            self.roomKey = SymmetricKey(data: Data(base64RoomKey.utf8))
        }
        self.onMessage = onMessage
        self.onDeviceLost = onDeviceLost
        self.onPeerFound = onPeerFound
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        stop()

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["app": "airchat"], serviceType: serviceType)
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()

        let browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        discoveredPeers.removeAll()
        connectedPeers.removeAll()
        seenMessageIDs.removeAll()
    }

    func connect(toPeer id: String) {
        guard let session = session, let peer = discoveredPeers[id] else { return }
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    var isRunning: Bool { session != nil }

    // MARK: - Crypto (AES-GCM, matches Android's `javax.crypto` envelope)

    private func encrypt(_ data: Data) -> Data {
        let sealed = try! AES.GCM.seal(data, using: roomKey)
        return sealed.combined!
    }

    private func decrypt(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: roomKey)
    }

    private static func decodeBase64URLSafe(_ string: String) -> Data? {
        var s = string
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    // MARK: - Sending

    func sendMessage(_ jsonStr: String) {
        guard let session = session else { return }
        var dict: [String: Any]
        if let data = jsonStr.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = obj
        } else {
            dict = ["raw": jsonStr]
        }
        if dict["id"] == nil { dict["id"] = UUID().uuidString }
        guard let id = dict["id"] as? String,
              let payload = try? JSONSerialization.data(withJSONObject: dict) else { return }
        seenMessageIDs.insert(id)
        let encrypted = encrypt(payload)
        broadcastToPeers(encrypted, excluding: nil)
    }

    private func broadcastToPeers(_ data: Data, excluding excludedID: String?) {
        guard let session = session else { return }
        let targets = session.connectedPeers.filter { $0.displayName != excludedID }
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }
}

// MARK: - MCSessionDelegate

extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                self.connectedPeers.insert(peerID.displayName)
            case .notConnected:
                self.connectedPeers.remove(peerID.displayName)
                self.onDeviceLost()
            default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let decrypted = decrypt(data) else { return }
        guard let str = String(data: decrypted, encoding: .utf8) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] else { return }
        let msgID = obj["id"] as? String ?? ""

        if !seenMessageIDs.contains(msgID) {
            seenMessageIDs.insert(msgID)
            DispatchQueue.main.async { self.onMessage(str) }
            // Re-broadcast the same (already encrypted) payload to everyone else exactly once.
            self.broadcastToPeers(data, excluding: peerID.displayName)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            self.discoveredPeers[peerID.displayName] = peerID
            self.onPeerFound(peerID.displayName, peerID.displayName)
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.discoveredPeers.removeValue(forKey: peerID.displayName) }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}
