import Foundation
import CryptoKit

/// AES-GCM helpers for the iOS mesh layer.
///
/// Mirrors `MeshManager.kt`:
///   - 12-byte random IV prepended to the payload
///   - 16-byte GCM auth tag appended at the end
///   - serialised layout: iv(12) || ciphertext || tag(16)
struct MeshCrypto {
    let key: SymmetricKey

    /// Builds the key from the base64url room key (the same string used for the
    /// XOR layer). Decoded to the raw 32 bytes.
    init(roomKeyBase64: String) {
        let cleaned = roomKeyBase64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = cleaned.padding(toLength: ((cleaned.count + 3) / 4) * 4,
                                     withPad: "=", startingAt: 0)
        if let raw = Data(base64Encoded: padded) {
            self.key = SymmetricKey(data: raw)
        } else {
            // Fallback: derive a key from the raw string so the app never crashes.
            self.key = SymmetricKey(data: Data(roomKeyBase64.utf8))
        }
    }

    func encrypt(_ plaintext: String) -> Data? {
        do {
            let box = try AES.GCM.seal(Data(plaintext.utf8), using: key)
            var combined = Data()
            combined.append(Data(box.nonce))              // 12 bytes
            combined.append(box.ciphertext)
            combined.append(box.tag)                      // 16 bytes
            return combined
        } catch {
            return nil
        }
    }

    func decrypt(_ data: Data) -> String? {
        guard data.count > 12 + 16 else { return nil }
        let nonceData = data.prefix(12)
        let tag = data.suffix(16)
        let ciphertext = data.dropFirst(12).dropLast(16)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let opened = try AES.GCM.open(box, using: key)
            return String(data: opened, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension Data {
    /// Hex helper, useful for debugging the mesh payload.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
