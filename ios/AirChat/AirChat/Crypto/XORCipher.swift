import Foundation

/// Bit-for-bit reimplementation of the web client's `encryptData` / `decryptData`
/// from `app.js`, so messages produced / consumed by the native app are
/// interoperable with browser and Android clients.
///
/// Web scheme:
///   encrypt: encodeURIComponent(plain) -> char-wise XOR with key -> base64
///   decrypt: base64 decode -> XOR with key -> decodeURIComponent
struct XORCipher {
    let key: String

    init(key: String) {
        self.key = key
    }

    /// Replicates JavaScript `encodeURIComponent` (the exact unescaped set:
    /// A-Z a-z 0-9 - _ . ! ~ * ' ( )).
    private func encodeURIComponent(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    func encrypt(_ plain: String) -> String {
        guard !key.isEmpty else { return plain }
        let encoded = encodeURIComponent(plain)
        let encBytes = Array(encoded.utf8)
        let keyBytes = Array(key.utf8)
        var out = Data(count: encBytes.count)
        for i in 0..<encBytes.count {
            out[i] = encBytes[i] ^ keyBytes[i % keyBytes.count]
        }
        return out.base64EncodedString()
    }

    func decrypt(_ base64: String) -> String? {
        guard !key.isEmpty else { return base64 }
        guard let data = Data(base64Encoded: base64) else { return nil }
        let keyBytes = Array(key.utf8)
        var out = Data(count: data.count)
        for i in 0..<data.count {
            out[i] = data[i] ^ keyBytes[i % keyBytes.count]
        }
        guard let xored = String(data: out, encoding: .utf8) else { return nil }
        return xored.removingPercentEncoding ?? xored
    }
}
