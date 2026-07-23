import Foundation

/// A minimal parsed HTTP/1.1 request (request line + headers).
struct HTTPRequest {
    var method: String
    var target: String          // e.g. "/index.html"
    var headers: [String: String]
}

enum HTTPParser {
    /// Parses a buffer up to the end of the HTTP headers. Returns the request
    /// and the byte count consumed when the header block is complete; nil while
    /// still waiting for more data.
    static func parse(_ buffer: Data) -> (HTTPRequest, Int)? {
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A] // \r\n\r\n
        guard let end = findSubsequence(buffer, separator) else { return nil }
        let headerBlock = buffer.subdata(in: 0..<end)
        guard let text = String(data: headerBlock, encoding: .utf8) else { return nil }

        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let request = HTTPRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            headers: headers
        )
        return (request, end + separator.count)
    }

    /// Returns the index of the first occurrence of `needle` in `haystack`.
    private static func findSubsequence(_ haystack: Data, _ needle: [UInt8]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for i in 0...(haystack.count - needle.count) {
            var match = true
            for j in 0..<needle.count {
                if haystack[haystack.startIndex + i + j] != needle[j] { match = false; break }
            }
            if match { return i }
        }
        return nil
    }
}
