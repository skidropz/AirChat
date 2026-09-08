//
//  WebContent.swift
//  AirChat
//
//  What the embedded server serves besides the WebSocket: the same PWA files the
//  Android app reads out of assets/, plus the two "viral sharing" endpoints.
//
//  On Android, /download-app streams the host's own .apk (context.applicationInfo
//  .sourceDir) so a friend with no internet can install the app from the hotspot.
//  iOS cannot do that — an .ipa is useless unless it is re-signed with the *target*
//  user's own Apple ID. So the endpoint degrades into a page that explains the
//  free-Apple-ID path (SideStore / AltStore / Sideloadly) and hands out a join link
//  that works with no install at all. If you drop a built AirChat.apk into the
//  bundle, /download-app serves that to Android visitors instead.
//

import Foundation

enum WebContent {

    static let webFolder = "WebApp"

    private static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "js": "application/javascript; charset=utf-8",
        "mjs": "application/javascript; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "webmanifest": "application/manifest+json",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "svg": "image/svg+xml",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff2": "font/woff2",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "txt": "text/plain; charset=utf-8",
        "apk": "application/vnd.android.package-archive"
    ]

    /// Root folder that the browser is allowed to read from.
    static var webRoot: URL {
        Bundle.main.bundleURL.appendingPathComponent(webFolder, isDirectory: true)
    }

    /// Absolute, sandboxed URL for a requested path. Returns nil for traversal
    /// attempts or missing files (equivalent of context.assets.open throwing).
    static func url(forPath path: String) -> URL? {
        var clean = path
        if clean.isEmpty || clean == "/" { clean = "/index.html" }
        if let hash = clean.firstIndex(of: "#") { clean = String(clean[clean.startIndex..<hash]) }
        if let q = clean.firstIndex(of: "?") { clean = String(clean[clean.startIndex..<q]) }
        clean = clean.removingPercentEncoding ?? clean
        let trimmed = clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty || trimmed.contains("..") { return nil }

        let candidate = webRoot.appendingPathComponent(trimmed).standardizedFileURL
        // Belt and braces: the standardised path must still start with webRoot.
        guard candidate.path.hasPrefix(webRoot.path) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue else {
            // /foo -> /foo/index.html, so folders behave like a web server would.
            let index = candidate.appendingPathComponent("index.html")
            return FileManager.default.fileExists(atPath: index.path) ? index : nil
        }
        return candidate
    }

    static func fileResponse(forPath path: String) -> HTTPResponse? {
        guard let url = url(forPath: path) else { return nil }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let ext = url.pathExtension.lowercased()
        let mime = mimeTypes[ext] ?? "application/octet-stream"
        var headers: [(String, String)] = []
        // Service workers must not be cached, the rest can be (matches sw.js intent).
        headers.append(("Cache-Control", ext == "js" && url.lastPathComponent == "sw.js"
                        ? "no-cache" : "public, max-age=3600"))
        return HTTPResponse(contentType: mime, headers: headers, body: data)
    }

    // MARK: - /download-app

    /// Android visitors get the APK when it is bundled; everybody else gets the
    /// install guide.
    static func appDownloadResponse() -> HTTPResponse {
        if let apk = bundledAPKURL(), let data = try? Data(contentsOf: apk) {
            return HTTPResponse(
                contentType: "application/vnd.android.package-archive",
                headers: [
                    ("Content-Disposition", "attachment; filename=\"AirChat.apk\""),
                    ("Content-Length", String(data.count))
                ],
                body: data)
        }
        return installGuideResponse()
    }

    /// Optional: run scripts/stage_artifacts.sh so the host's bundle carries the real
    /// Android APK; then an iPhone host can still seed Android phones with the app.
    /// Without it the endpoint degrades to the guide page (an .ipa we could not sign
    /// for the visitor anyway).
    static func bundledAPKURL() -> URL? {
        let root = Bundle.main.bundleURL
        for rel in ["AirChat.apk", "WebApp/AirChat.apk", "WebApp/share/AirChat.apk",
                    "share/AirChat.apk", "Resources/AirChat.apk"] {
            let u = root.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: - /ios-install

    /// The guide is a shared web asset so Android hosts, iOS hosts and the PWA all
    /// show the same instructions. A redirect (rather than an inline page) keeps a
    /// single source of truth in app/src/main/assets/install.html.
    static func installGuideResponse() -> HTTPResponse {
        .redirect(to: "/install.html")
    }

    /// `/download-app/AirChat.apk` and `/download-app/AirChat-unsigned.ipa`.
    ///
    /// Android hosts can stream their own package (applicationInfo.sourceDir). An iOS
    /// host cannot install anything for a friend — but it CAN hand out the artifacts a
    /// friend needs to sign themselves, which is the whole sideload workflow. Drop the
    /// files into ios/AirChat/AirChat/WebApp/share/ (scripts/stage_artifacts.sh)
    /// and this endpoint serves them straight off the phone.
    static func artifactDownload(named requested: String) -> HTTPResponse {
        let name = requested.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let safe = name.split(separator: "/").last.map(String.init) ?? ""
        let ext = (safe as NSString).pathExtension.lowercased()
        let base = (safe as NSString).deletingPathExtension
        let allowedExtensions = ["apk", "ipa", "zip", "txt"]
        let isSafeName = base.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        guard !safe.isEmpty, isSafeName, allowedExtensions.contains(ext) else {
            return .notFound("Filă necunoscută / unknown file")
        }
        for dir in ["share", "WebApp/share", "Resources/share"] {
            let url = Bundle.main.bundleURL.appendingPathComponent(dir).appendingPathComponent(safe)
            if let data = try? Data(contentsOf: url), data.count > 0 {
                let mime: String
                switch ext {
                case "apk": mime = "application/vnd.android.package-archive"
                case "ipa": mime = "application/octet-stream"
                case "zip": mime = "application/zip"
                default: mime = "text/plain; charset=utf-8"
                }
                return HTTPResponse(contentType: mime,
                                    headers: [("Content-Disposition", "attachment; filename=\"\(safe)\"")],
                                    body: data)
            }
        }
        return .text("Not bundled in this build. Put the file in ios/AirChat/AirChat/WebApp/share/ and rebuild (see scripts/stage_artifacts.sh).",
                     status: 404)
    }

    // MARK: - /api/status

    static func statusResponse(port: UInt16, hostIP: String, shortCode: String,
                               clients: Int, uptime: TimeInterval) -> HTTPResponse {
        let json: [String: Any] = [
            "app": "AirChat",
            "platform": "iOS",
            "port": Int(port),
            "hostIP": hostIP,
            "shortCode": shortCode,
            "clients": clients,
            "uptime": Int(uptime),
            "hotspot": NetworkInfo.isPersonalHotspotUp,
            "interfaces": NetworkInfo.all.map { ["name": $0.name, "ip": $0.ip, "kind": $0.kind.rawValue] }
        ]
        let data = (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(contentType: "application/json; charset=utf-8", body: data)
    }
}
