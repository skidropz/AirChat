# AirChat for iOS

Same app, same wire protocol, one more phone becoming the server. This port keeps the
Android codebase untouched apart from the shared web bundle (`app/src/main/assets/`),
which the iOS target builds straight from — there is exactly one implementation of the
chat UI, the crypto and the WebSocket protocol.

```
                     ┌──────────────────────────────────────────────┐
   browser / PWA ───►│  iPhone host: HTTP + WebSocket on :8080      │◄─── Android host
   laptop ──────────►│  Network.framework listener (Sources/Net)   │     (serves the same page)
   Android app ─────►│        ▲                        ▲            │
                     │        │ WKWebView (this phone) │ Bonjour    │
                     │  MultipeerConnectivity mesh ◄──┴── other iPhones
                     └──────────────────────────────────────────────┘
```

* **iPhone is the server.** `AirChatServer` is a hand-written HTTP/1.1 + RFC 6455
  WebSocket server on `NWListener`, ported 1:1 from `LocalServer.kt` (NanoHTTPD +
  NanoWSD are JVM-only). It serves `index.html#<roomKey>`, the 4-letter short code
  redirect, the captive-portal intercepts and the `/download-app` sharing endpoints.
* **The host phone renders the very same page** its guests get, inside a `WKWebView`
  loaded from `http://127.0.0.1:8080`, so no second UI exists to keep in sync.
* **Mesh** = MultipeerConnectivity (BLE discovery + peer-to-peer Wi-Fi) with the same
  AES-256-GCM envelope as Android's Nearby Connections, including relay-through-a-third-phone.

---

## 1. Getting it onto a phone (no paid developer account)

**Be clear about the constraint:** TestFlight *requires* the Apple Developer Program
($99/yr) — there is no way to publish to TestFlight with a free account, and a hosted
`.ipa` cannot be installed on iOS the way Android installs a hosted `.apk`, because every
binary must be signed for the *specific device* by an Apple ID that the *recipient* owns.
The workaround is to let the recipient's own free Apple ID do the signing. All of these
are free; a free Apple ID may sign at most 3 sideloaded apps, ~10 new App IDs per week,
and its certificates expire after 7 days.

| Route | Needs a computer | Needs an account | Expiry | Notes |
| --- | --- | --- | --- | --- |
| **A. Xcode → Run** (free provisioning) | Mac with Xcode | free Apple ID | 7 days | Best for the developer. Section 2. |
| **B. Sideloadly + the CI `.ipa`** | Win/Mac | free Apple ID | 7 days | Easiest for friends: they never open Xcode. |
| **C. SideStore / AltStore** | one-time pairing | free Apple ID | auto-refresh | Re-signs itself; add this phone's own `/download-app` as a source. |
| **D. TrollStore** | none | none | never | Only iOS 14.0–16.6.1 / 17.0. Bypasses signing entirely. |
| **E. TestFlight** | you archive | **paid $99** | 90 days | `./scripts/build_ipa.sh --team <ID> --archive`, upload via Transporter. |
| **F. AltStore PAL / other EU storefronts** | none | EU account | storefront rules | DMA-era distribution, EU only. |

AirChat needs no push, no App Groups, no iCloud, no entitlements at all
(`AirChat.entitlements` is intentionally empty), so every free route above works. The
background keep-alive trick is exactly the thing App Review rejects — which is *why*
this app is distributed this way. Treat it as the usual personal-use sideloading that
Apple tolerates; don't ship it to strangers through a shared enterprise certificate.

---

## 2. Build & install from Xcode (route A)

1. `open ios/AirChat/AirChat.xcodeproj` — no Pods, no SPM, no codegen step needed.
   A first build re-syncs `app/src/main/assets/` into the bundle automatically
   (that is what the "Sync shared web app" phase in the target does).
2. Target ▸ Signing & Capabilities: set **Team** to your personal Apple ID
   ("*NAME* (Personal Team)") and leave the bundle id `com.skidropz.airchat`. If it is
   already taken on your account, append something, e.g. `com.skidropz.airchat.mihai`.
   No provisioning profile download, no paid membership.
3. Plug the iPhone in, trust the computer, pick it as the run destination → **Run**.
   First launch: the app prompts for **Local Network**, **Location**, **Microphone** — all
   three are required (see §5). Then, if iOS blocks the launch:
   Settings ▸ General ▸ VPN & Device Management ▸ tap your Apple ID ▸ **Trust**.
4. Re-run every 7 days (Xcode refreshes the signature), or let SideStore do it.

### Without Xcode (routes B/C)

```bash
git clone https://github.com/skidropz/AirChat && cd AirChat
./ios/AirChat/scripts/build_ipa.sh            # → ios/AirChat/build/AirChat-unsigned.ipa
```
or let CI do it — first enable the workflow once (it ships at `ios/ci/ios-ipa.yml`
because pushing straight into `.github/workflows/` needs the `workflows` permission):

```bash
mkdir -p .github/workflows && git mv ios/ci/ios-ipa.yml .github/workflows/ios-ipa.yml && git push
```

then Actions ▸ “iOS build (unsigned .ipa for sideloading)” ▸ **Run workflow**
▸ download `AirChat-unsigned-ipa`. Hand that file (or its download link) to whoever
installs it: they drop it on Sideloadly, enter **their own** Apple ID, and install.
AltStore users can just copy the `.ipa` into `~/Library/AltStore/Apps` and it appears in
their store app on the phone.

To bundle the Android APK and the `.ipa` into the iOS app so *the iPhone host* serves
them to every connected friend:

```bash
./ios/AirChat/scripts/stage_artifacts.sh      # writes AirChat/WebApp/share/
./ios/AirChat/scripts/build_ipa.sh --sync-share
```

---

## 3. What is where

```
ios/AirChat/
├── AirChat.xcodeproj/                committed, generated — see scripts/generate_project.py
├── project.yml                       XcodeGen spec for the same target (optional path)
├── scripts/
│   ├── generate_project.py   writes the .xcodeproj from whatever sources exist on disk
│   ├── sync_web_assets.sh    app/src/main/assets → WebApp (runs as a build phase too)
│   ├── make_assets.py        app icon + launch logo from ic_launcher-playstore.png
│   ├── build_ipa.sh          unsigned .ipa, or archive for TestFlight with --team
│   └── stage_artifacts.sh    puts APK / .ipa / INSTALL.txt into the served share folder
└── AirChat/
    ├── Info.plist                    local network, Bonjour, background audio, ATS, airchat://
    ├── AirChat.entitlements          empty on purpose (§1)
    ├── Sources/
    │   ├── AppDelegate.swift, SceneDelegate.swift
    │   ├── Net/AirChatServer.swift   listener, routing, history, broadcast   (= LocalServer.kt)
    │   ├── Net/HTTPRequest.swift     HTTP/1.1 parser + response writer
    │   ├── Net/WebSocket.swift       RFC 6455 frames + handshake
    │   ├── Net/WebContent.swift      bundle files, /download-app, /install.html, /api/status
    │   ├── Net/NetworkInfo.swift     getifaddrs: hotspot vs Wi-Fi vs cellular IP (= getSmartIpAddress)
    │   ├── Mesh/MeshManager.swift    MultipeerConnectivity + relay            (= MeshManager.kt)
    │   ├── Mesh/AESGCM.swift         CryptoKit AES-256-GCM, IV||ct||tag
    │   ├── Bridge/AirChatBridge.swift  JS ⇄ Swift (battery, theme, mic, photos, haptics)
    │   ├── Bridge/NativeRecorder.swift AVAudioRecorder → m4a base64 data URL
    │   ├── Bridge/ImagePickerCoordinator.swift PHPicker + camera, resized to 800px JPEG
    │   ├── Sensors/LocationProvider.swift  CoreLocation position + compass heading
    │   ├── Host/AppRuntime.swift     owns server/mesh/sensors, deep links, settings
    │   ├── Host/KeepAlive.swift      silent audio session = background serving
    │   ├── Host/AirChatBonjour.swift NetService publish + browse for nearby rooms
    │   ├── Room/RoomState.swift      room key + short code, keychain-backed
    │   ├── UI/HomeViewController.swift  native bar + WKWebView + keyboard + banners
    │   ├── UI/HostPanelView.swift    SwiftUI control sheet (everything host-related)
    │   ├── UI/RuntimeModel.swift     ObservableObject mirror for that sheet
    │   └── Util/{QRCode,Haptics,Localization}.swift
    ├── WebApp/                       copy of the Android assets (folder reference)
    └── Resources/Assets.xcassets     AppIcon, SplashLogo, AccentColor, SplashBackground
```

---

## 4. Android ⇄ iOS differences, and how each one is handled

Every row is a platform wall, not a missing feature — the behaviour is reached by a
different mechanism on iOS.

| Android | iOS | How it works here |
| --- | --- | --- |
| `NanoHTTPD` + `NanoWSD` | no such library | `Sources/Net/*`, ~700 lines on Network.framework |
| Host serves its own `base.apk` at `/download-app` | a hosted `.ipa` cannot be installed | `install.html` guide + serves a staged `AirChat.apk`/`AirChat-unsigned.ipa` if present |
| Foreground service keeps the server alive | background apps are frozen | silent looping `AVAudioPlayer` + `UIBackgroundModes: audio` (`KeepAlive`), toggled in the Server panel |
| `WifiManager` hotspot / `LocalOnlyHotspot` | **no public API to enable tethering, at any tier** | user turns on Personal Hotspot; the app detects `bridge0`/`en6`/`ap1`, shows whether it is up, and deep-links `App-prefs:WI-Fi&tethering` |
| Captive portal auto-popup | `:80` binds only on IPv4, is refused in the simulator, and can be denied on device | a **best-effort second listener** on `:80` (`Config.servePortalPort`) answers `/generate_204`, `/hotspot-detect.html` and `success.txt`; QR / short code / Bonjour tap stays the documented path |
| Nearby Connections `P2P_CLUSTER` | not on iOS | MultipeerConnectivity (`airchat-mesh`) — see the caveat in §5 |
| `AndroidInterface` sync JS calls, `WebChromeClient` mic + file chooser | WKWebView: async replies only, no `getUserMedia` on http origins, no file input | `WKScriptMessageHandlerWithReply` bridge; native `AVAudioRecorder` for walkie-talkie; `PHPicker` for images. A `window.AndroidInterface` shim in `airchat-bridge.js` keeps `app.js` shared |
| `SensorManager` accelerometer+magnetometer azimuth | `deviceorientation` is not reliable in WKWebView | CoreLocation `CLHeading` → `updateMyHeading()` (the same source Safari feeds web pages) |
| `Vibrator.vibrate(500)` for BUZZ | no vibration API for apps | CoreHaptics pattern + `UIImpactFeedbackGenerator` fallback |
| `BatteryManager` | browser API unavailable | bridge reads `UIDevice.batteryLevel`, cached for `app.js` |
| `AlertDialog` for a discovered mesh node | no BT scan permission dance needed | same alert + `NSLocalNetworkUsageDescription` prompt instead |
| `startActivity(WIFI_SETTINGS)` | — | `UIApplication.openSettingsURLString` fallback chain |

**Consequence to know before a field test:** the *mesh* does **not** interoperate
across platforms (Google Nearby and MultipeerConnectivity are unrelated protocols), and
neither works through a browser. What always works, iPhone ⇄ Android ⇄ laptop, is the
**HTTP/WebSocket room**, which is also the only thing non-app users need. Cross-platform
range extension therefore means "one more phone hosting", not "one more mesh hop".

---

## 5. Testing checklist

Run this once after a build; it is also the quickest way to see which permission is missing.

1. **Self-test** — launch AirChat on the host iPhone. The bar over the chat must read
   `<ip>:8080/<CODE>` with a green dot; the room list shows you alone. If the dot is
   red, open the Server panel (rightmost icon): either Local Network was denied or the
   port is taken.
2. **Loopback** — `curl http://127.0.0.1:8080/api/status` from the Mac with Xcode
   attached shows the same JSON the guide page reads.
3. **Second device on Wi-Fi** — join the same router, open `http://<ip>:8080/<CODE>`,
   or scan the QR from the panel. Two names in the room list = server + WebSocket OK.
4. **Hotspot** — turn on Personal Hotspot on the iPhone, join it from the other device,
   open `http://172.20.10.1:8080/<CODE>` (that is the address iOS gives hotspot clients;
   the panel shows the live one). The panel must flip to “Personal Hotspot is on”.
5. **Background** — lock the host with "Keep serving when locked" ON, send a message
   from the other device, confirm it arrives. Then turn the toggle OFF and confirm the
   client goes stale (red status dot after ~10 s). This proves the keep-alive is what
   does the work.
6. **E2EE** — the QR/`airchat://` link must carry `#<base64 key>`. Without it the page
   asks for the room code and cannot decrypt — i.e. the server never sees the key.
7. **Voice + images + BUZZ** — hold the mic on the host phone (native recorder), send a
   photo (PHPicker), hit ⚡ and feel haptics on both phones.
8. **Mesh (2 iPhones)** — same Wi-Fi or adjacent, Server panel ▸ Mesh must list the peer;
   accept the "AirChat detected" prompt, then check the peer count. Airplane mode with
   Wi-Fi+BT on should still mesh (AWDL/BLE), which is the point.
9. **Android host → iPhone client** — run the Android app, join its room from the
   iPhone's Server panel ▸ "Rooms around you" (Bonjour) or by typing its address:
   proves both hosts are wire-compatible.
10. **Simulator is not enough** — MultipeerConnectivity, Local Network prompts and
    inbound connections all behave differently there. Use real devices.

---

## 6. Known limits

* One host per room; only the *host* iPhone gets voice notes natively (a browser on a
  plain http origin has no `getUserMedia`, same as Android's browser clients).
* No `Add to Home Screen` PWA offline cache benefit inside our own WebView; that path
  is for guests and works in Safari.
* Low Power Mode can still suspend the server; a force-quit always does.
* Personal Hotspot needs a carrier plan that allows tethering — nothing in the app can
  change that.
* iOS 15 minimum (`WKScriptMessageHandlerWithReply`, `PHPicker`, `CryptoKit`).
