//
//  AESGCM.swift
//  AirChat
//
//  Wire-compatible with MeshManager.kt on Android:
//      payload = IV(12 bytes) || ciphertext || GCM tag(16 bytes)
//  Java's "AES/GCM/NoPadding" emits ciphertext||tag, which is what CryptoKit
//  exposes as two separate fields, so we concatenate by hand.
//

import Foundation
import CryptoKit
import Security

enum AirChatCrypto {

    static let ivLength = 12
    static let tagLength = 16

    static func key(fromBase64URL base64: String) -> SymmetricKey? {
        guard let data = RoomState.decodeBase64URL(base64), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    static func seal(_ plaintext: Data, key: SymmetricKey) -> Data? {
        var bytes = [UInt8](repeating: 0, count: ivLength)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let nonce = AES.GCM.Nonce(data: Data(bytes))
        guard let box = try? AES.GCM.seal(plaintext, using: key, nonce: nonce),
              let combined = box.combined else { return nil }
        // CryptoKit's `combined` is already nonce||ciphertext||tag; strip the nonce
        // so the layout matches Android's (which prefixes the IV itself).
        return combined.dropFirst(ivLength)
    }

    static func open(_ payload: Data, key: SymmetricKey) -> Data? {
        guard payload.count > ivLength + tagLength else { return nil }
        let iv = payload.subdata(in: 0..<ivLength)
        let body = payload.subdata(in: ivLength..<payload.count)
        guard let box = try? AES.GCM.SealedBox(combined: iv + body) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}
