# 📱 AirChat for iOS

A native iOS port of [AirChat](../Readme.md) — an offline, peer-to-peer messaging app. The
iPhone becomes the **server**: it runs an HTTP + WebSocket listener and serves the *exact same*
web app the Android phone serves, so an iPhone can host a room full of Android phones, laptops
and other iPhones — over its Wi-Fi hotspot, with no internet, no accounts, no cloud.

```
app/src/main/assets/          ← the shared "brain" (chat UI, E2EE, protocol)
ios/AirChat/AirChat/          ← the iOS host shell (no fork, no drift)
```

The web bundle is not duplicated: a build phase copies `app/src/main/assets/` straight into the
app bundle, so the two platforms cannot drift apart.

---

## What it does (feature parity with Android)

| Feature | How it works on iOS |
| --- | --- |
| Host a room (HTTP + WebSocket) | `Network.framework` `NWListener` — hand-written HTTP/1.1 + RFC 6455 server, protocol-identical to Android's NanoHTTPD + NanoWSD (`LocalServer.swift`) |
| Chat UI | `WKWebView` loading the same `index.html` at `http://127.0.0.1:8080/#<roomKey>` |
| Short 4-letter code | `http://<ip>:8080/CODE` → redirect to `/index.html#<roomKey>` (key only travels in the URL fragment) |
| Captive portal | `generate_204` / `hotspot-detect.html` / `success.txt` intercept kept for parity |
| Voice notes | `AVAudioRecorder` → `.m4a` handed to the page (WKWebView refuses `getUserMedia` on `http://`) |
| Photos | `PHPickerViewController` (no photo-library permission prompt) |
| BUZZ haptics | `CoreHaptics` + fallback vibration |
| Compass ("Find my friend") | `CoreLocation` heading → `updateMyHeading()` |
| GPS share | `CoreLocation` → `updateMyLocation()` |
| Battery status | `UIDevice.batteryLevel`, cached and pushed through the bridge |
| Mesh networking | `MultipeerConnectivity` (BLE discovery + peer-to-peer Wi-Fi), same **AES-GCM** envelope as Android's Nearby Connections (`MeshManager.swift`) |
| Nearby-room discovery | Bonjour `_airchat-http._tcp` advert + browse → tap-to-join list |
| Keep serving when locked | silent looping `AVAudioSession` (with an honest toggle in the Server panel) |
| Deep link | `airchat://join?host=…&port=…&code=…` URL scheme |

### The one honest workaround

Apple will not let a normal app own port 80 or switch the hotspot on, so the iOS host does
**not** get the automatic "captive portal popup" the Android host gets. Instead of the popup you
get three things that produce the same result:

1. a **QR code** and a **4-letter code** (typed once),
2. a **tap-to-join list** of nearby rooms via Bonjour,
3. a **deep link** (`airchat://join…`) from the install page.

Same result: nobody types a URL except you, once.

And because an iPhone has no `.apk` to hand out, `/download-app` on an iOS host sends Apple
devices to the install guide and everyone else to the GitHub releases (the Android host serves
its own APK in-band).

---

## Architecture

```
┌───────────────────────────── ViewController ─────────────────────────────┐
│  native header: invite link · QR · Server panel (⚙)                     │
│  ┌─────────────────────────────────────────────────────────────────────┐ │
│  │  WKWebView — index.html from http://127.0.0.1:8080/#<roomKey>       │ │
│  │        airchat-bridge.js  ⇄  NativeBridge (WKScriptMessageHandler) │ │
│  └───────────────────────────────▲─────────────────────────────────────┘ │
│            LocalServer (NWListener)   MeshManager (MultipeerConnectivity)│
│            HTTP/1.1 + WebSocket       AES-GCM envelope, dedup by id      │
└──────────────────────────────────────────────────────────────────────────┘
```

- `LocalServer.swift` — HTTP/1.1 + RFC 6455 server, serves the shared bundle, keeps the last 50
  messages and re-syncs them to every new client.
- `MeshManager.swift` — BLE discovery + peer-to-peer Wi-Fi, AES-GCM (CryptoKit), re-broadcasts a
  payload to every other peer exactly once (deduped by message id) → range extension.
- `NativeBridge.swift` — the `airchat` `WKScriptMessageHandlerWithReply` that `airchat-bridge.js`
  detects and builds `window.AndroidInterface` / `window.AirChatNative` on top of.
- `BackgroundKeepAlive.swift` — the silent audio session that keeps the socket alive when locked.

---

## Build & install — no $99 developer account, no App Store

Requirements: **Xcode 15+ on macOS, iOS 15.0 minimum**. Zero third-party dependencies — no
CocoaPods, no SPM packages, no entitlements.

### Option A — Xcode with a free Apple ID

1. Open `ios/AirChat/AirChat.xcodeproj`.
2. Select the **AirChat** target → *Signing & Capabilities* → pick your **Personal Team**
   (a free Apple ID works; the bundle id `com.skidropz.airchat` may need a tweak to something
   unique to you, e.g. `com.yourname.airchat`).
3. Run on a device. The build phase re-syncs `app/src/main/assets/` automatically.

### Option B — build an unsigned `.ipa` and sideload

```bash
./ios/AirChat/scripts/build_ipa.sh    # → ios/AirChat/build/AirChat-unsigned.ipa
```

Then sign it with **Sideloadly** (Windows/Mac), **AltServer/AltStore** or **SideStore** using
your own Apple ID. Free accounts allow 3 sideloaded apps, a 7-day certificate (the tools refresh
it for you). On old iOS, **TrollStore** installs the IPA with no signing at all.

### Option C — CI

No Mac? Enable the bundled workflow once:

```bash
git mv ios/ci/ios-ipa.yml .github/workflows/
```

GitHub Actions then builds `AirChat-unsigned.ipa` on every push to `main` that touches `ios/**`
or the shared assets, and uploads it as an artifact.

---

## Platform limits you should know

- **No captive-portal popup.** iOS can't own port 80 or toggle the hotspot; use the QR code,
  short code or Bonjour list instead (see above).
- **Background freeze.** iOS suspends backgrounded apps. Keep AirChat open, or enable
  *Keep serving when locked* in the Server panel (⚙). The panel is honest about the battery cost:
  the silent-audio trick is exactly what would not survive App Store review — which is why this
  app is sideloaded, not distributed.
- **Everyone must be on the same network.** Guests join the host's Wi-Fi hotspot; mesh peers
  must have Bluetooth on and be near each other.
- **First-run permissions.** Microphone, location and local-network access are requested on
  first use; grant them or voice notes / compass / discovery won't work.

## Field-test checklist

1. Airplane Mode **on**, Personal Hotspot **on** (Settings → Personal Hotspot).
2. Launch AirChat — note the IP, short code and QR in the header.
3. A second phone joins your hotspot and opens `http://<ip>:8080/<code>` — it should land in the
   chat with no URL typing beyond that.
4. Send text / image / voice note / BUZZ both ways; verify the compass points at the other phone.
5. Lock the host with *Keep serving when locked* on and confirm messages still arrive.
6. On a second iPhone with AirChat, open ⚙ → *Nearby rooms* → tap to join (Bonjour).
