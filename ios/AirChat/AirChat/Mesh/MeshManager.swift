import Foundation
import MultipeerConnectivity

/// Delegate notified about messages and topology changes in the iOS mesh.
protocol MeshManagerDelegate: AnyObject {
    /// A decrypted raw wire text arrived from a mesh peer.
    func mesh(_ mesh: MeshManager, didReceiveMessage text: String)
    /// The set of connected peers changed.
    func mesh(_ mesh: MeshManager, connectedPeersChanged peers: [String])
    /// A new peer was discovered (for optional UI prompt).
    func mesh(_ mesh: MeshManager, didDiscoverPeer name: String, id: MCPeerID)
}

/// iOS mesh networking built on `MultipeerConnectivity`.
///
/// Replaces Google Nearby Connections from the Android app. iOS devices discover
/// each other over Bonjour (Wi-Fi / Bluetooth) and relay AES-GCM-encrypted chat
/// payloads, mirroring `MeshManager.kt` (encrypt → broadcast → dedup → re-broadcast).
final class MeshManager: NSObject {
    weak var delegate: MeshManagerDelegate?

    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let crypto: MeshCrypto

    private var seenIds = Set<String>()
    private let lock = NSLock()

    init(displayName: String, roomKeyBase64: String) {
        self.peerID = MCPeerID(displayName: displayName)
        self.crypto = MeshCrypto(roomKeyBase64: roomKeyBase64)
        self.session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)

        let info = ["name": displayName]
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: info,
            serviceType: AppConstants.meshServiceType
        )
        self.browser = MCNearbyServiceBrowser(peer: peerID, serviceType: AppConstants.meshServiceType)
        super.init()

        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        lock.lock(); seenIds.removeAll(); lock.unlock()
    }

    var connectedPeerNames: [String] {
        session.connectedPeers.map { $0.displayName }
    }

    // MARK: - Send

    /// Encrypts and sends a raw wire text to all connected peers.
    /// Ensures the payload carries an `id` for deduplication.
    func send(_ rawText: String) {
        let text = ensureId(in: rawText)
        guard let data = crypto.encrypt(text) else { return }
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            // ignore send failures (peer gone, etc.)
        }
    }

    /// Injects a random `id` if the JSON object doesn't already carry one.
    private func ensureId(in text: String) -> String {
        guard let data = text.data(using: .utf8),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return text
        }
        if obj["id"] == nil {
            obj["id"] = UUID().uuidString
        }
        if let updated = try? JSONSerialization.data(withJSONObject: obj),
           let result = String(data: updated, encoding: .utf8) {
            if let id = obj["id"] as? String {
                lock.lock(); seenIds.insert(id); lock.unlock()
            }
            return result
        }
        return text
    }
}

// MARK: - MCSessionDelegate

extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.mesh(self, connectedPeersChanged: self.connectedPeerNames)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let text = crypto.decrypt(data) else { return }
        guard let jsonData = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let id = obj["id"] as? String else {
            // No id → can't dedup; forward once.
            DispatchQueue.main.async { self.delegate?.mesh(self, didReceiveMessage: text) }
            return
        }
        lock.lock()
        let isNew = !seenIds.contains(id)
        if isNew { seenIds.insert(id) }
        lock.unlock()
        guard isNew else { return }

        DispatchQueue.main.async { self.delegate?.mesh(self, didReceiveMessage: text) }
        // Re-broadcast to other peers (mesh relay), matching Android behaviour.
        if !session.connectedPeers.isEmpty {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertising / Discovery

extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept, mirroring Android's `acceptConnection`.
        invitationHandler(true, session)
    }
}

extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        delegate?.mesh(self, didDiscoverPeer: peerID.displayName, id: peerID)
        // Auto-connect (Android shows a prompt; we connect immediately for parity of mesh behaviour).
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.mesh(self, connectedPeersChanged: self.connectedPeerNames)
        }
    }
}
