//
//  RoomState.swift
//  AirChat
//
//  The E2EE room key + the 4-character short code. Byte-compatible with the
//  Android side (MainActivity.onCreate): 32 random bytes, base64 URL_SAFE with
//  padding, transported to clients only inside the URL fragment.
//

import Foundation
import Security

final class RoomState {

    static private let keyTag = "com.skidropz.airchat.roomkey"
    static private let codeTag = "com.skidropz.airchat.roomcode"

    private let defaults = UserDefaults.standard

    /// base64url(32 bytes) — the XOR key the browser uses and the AES-256-GCM key
    /// the mesh uses. Sent to clients in the URL fragment only.
    private(set) var keyBase64URL: String
    private(set) var shortCode: String

    static let keyCodeAlphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    init() {
        let storedKey = RoomState.readKeychain() ?? defaults.string(forKey: RoomState.keyTag)
        if let storedKey, RoomState.isValidKey(storedKey) {
            keyBase64URL = storedKey
        } else {
            keyBase64URL = RoomState.newKey()
        }

        let storedCode = defaults.string(forKey: RoomState.codeTag)
        if let storedCode, storedCode.count == 4 {
            shortCode = storedCode.uppercased()
        } else {
            shortCode = RoomState.newCode()
        }
        persist()
    }

    // MARK: - Generation

    static func newKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            for i in 0..<bytes.count { bytes[i] = UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func newCode() -> String {
        (0..<4).map { _ in keyCodeAlphabet.randomElement() ?? "A" }.joined()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    static func decodeBase64URL(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    static func isValidKey(_ candidate: String) -> Bool {
        guard let data = decodeBase64URL(candidate) else { return false }
        return data.count == 32
    }

    // MARK: - Mutation

    /// New room: fresh key + fresh short code. On Android this happens implicitly
    /// at every launch; here it is an explicit action so the room stays stable.
    func rotate() {
        keyBase64URL = RoomState.newKey()
        shortCode = RoomState.newCode()
        persist()
    }

    /// Join somebody else's room by adopting their key/code.
    func adopt(key: String? = nil, code: String? = nil) {
        if let key, RoomState.isValidKey(key) { keyBase64URL = key }
        if let code, code.count == 4 { shortCode = code.uppercased() }
        persist()
    }

    var joinURLFragment: String { "#" + keyBase64URL }

    private func persist() {
        defaults.set(keyBase64URL, forKey: RoomState.keyTag)
        defaults.set(shortCode, forKey: RoomState.codeTag)
        RoomState.saveKeychain(keyBase64URL)
    }

    // MARK: - Keychain

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func saveKeychain(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyTag
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
