# 📡 AirChat

AirChat is an offline, peer-to-peer messaging app for **Android and iPhone**. It basically turns your phone into a portable communication hub that works completely without the internet. 

I originally built this for situations where networks are either dead or completely overloaded—think hiking in the mountains, packed music festivals, protests, or power outages.

---

### Why use AirChat?

The coolest part about AirChat is that **only one person needs to have the app installed**. 

If you have the app on your phone — Android **or** iPhone — your friends on the other platform, on laptops, or on older devices don't need to download anything. They just connect to your phone's Wi-Fi hotspot, and a "Captive Portal" pops up (just like when you connect to hotel Wi-Fi). It drops them right into the chat via their browser.

> On the iPhone the portal popup part is Apple's no-go zone (an app can neither switch the hotspot on nor own port 80), so instead of the popup you get a QR code, a 4-letter code and a tap-to-join list of nearby rooms. Same result: nobody types a URL except you, once. 

* **100% Offline:** Works in Airplane Mode or in the middle of nowhere.
* **Viral App Sharing:** If your friend *does* want the native app but has no internet to get it from the Play Store, AirChat hosts its own `.apk`. They can download it directly from your hotspot. An iPhone host serves that same APK to Android guests, plus an install guide for fellow iPhone users.
* **Hybrid Mesh Networking:** If multiple people have the app *on the same platform*, the phones find each other via Bluetooth and form a mesh. This extends the range—Phone A can talk to Phone C by bouncing the signal through Phone B. Android uses Google Nearby Connections, iOS uses MultipeerConnectivity, both with the same AES-GCM envelope.

---

## 📱 AirChat on iPhone (new)

The iPhone **is** the server: `Network.framework` runs an HTTP + WebSocket listener
that serves the exact same web app the Android phone serves, so an iPhone can host a
room full of Android phones, laptops and other iPhones — offline, over its hotspot.

* **Native app, shared brain.** The chat UI, the E2EE and the protocol live in one place (`app/src/main/assets/`); the iOS target compiles straight from it. No fork, no drift.
* **Voice notes still work** — WKWebView refuses `getUserMedia` on a plain `http://` origin, so the host app records with `AVAudioRecorder` and hands the page an `.m4a` (which, unlike Android's `webm`, every browser can actually play).
* **Photos** via `PHPicker` (no photo-library permission prompt), haptic BUZZ via CoreHaptics, compass via CoreLocation's heading — the same feed Safari gives web pages.
* **It keeps serving when locked** through a silent background audio session, because iOS otherwise freezes the socket. There's a switch for it in the Server panel, and the panel tells you honestly what each toggle costs you.
* **Bonjour** (`_airchat-http._tcp`) replaces "we found a nearby node, connect?": an iPhone sees the room next to it and joins with one tap, no IP typing.

Install it — **no $99 developer account, no App Store** — with your free Apple ID via
Xcode, Sideloadly, SideStore/AltStore, or the `.ipa` that CI builds. TrollStore if you're
on an old iOS. The why/how of each route, the exact platform limits and a field-test
checklist are in **[ios/README.md](ios/README.md)**.

```bash
./ios/AirChat/scripts/build_ipa.sh    # → ios/AirChat/build/AirChat-unsigned.ipa
open ios/AirChat/AirChat.xcodeproj   # …or just hit Run with a free Apple ID
```
* **Total Privacy (E2EE):** There are no servers, no cloud, and no accounts. Everything is encrypted end-to-end using AES-GCM (for native mesh) and WebCrypto (for browser users). Keys are passed via URL fragments (`#`) so they never touch the server in plaintext.

---

## 📸 Screenshots

<p float="left">
<img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20principala%CC%86.png" alt="Main Interface" width="300">
    <img src="https://github.com/skidropz/AirChat/blob/main/Chatul.png" alt="Chat" width="300">
<img src="https://github.com/skidropz/AirChat/blob/main/Codul%20QR.png" alt="QR Code" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20din%20browser.png" alt="Browser UI" width="300">
      <img src="https://github.com/skidropz/AirChat/blob/main/Chatul%20din%20browser.png" alt="Browser Chat" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Lista%CC%86%20utilizatori.png" alt="User List" width="300">
    <img src="https://github.com/skidropz/AirChat/blob/main/Ga%CC%86sire%20prieteni.png" alt="Compass" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%CC%86%20Mesh.png" alt="Mesh Interface" width="300">
</p>

---

## 🚀 What's inside v3.0?

I've completely overhauled how AirChat works under the hood for this release. 

* **Private 1-on-1 Chats:** You're no longer restricted to the global room. You can tap on anyone's name and open a private, E2E encrypted chatroom directly inside the local network.
* **Captive Portal Auto-Login:** I tweaked the NanoHTTPD server to intercept iOS/Android connectivity checks. Now, when people join your hotspot, their OS forces the browser open right into the chat.
* **PWA Support:** iOS and PC users can now hit "Add to Home Screen". The app will behave exactly like a native app, hiding the Safari/Chrome UI bars.
* **Easy PC Connection:** Scanning a QR code from a laptop webcam is awful. Now, the app generates a short 4-letter code (like `A7X2`). You just type `http://192.168.43.1:8080/A7X2` in your browser, and the server automatically redirects you and handles the crypto keys.
* **Bulletproof Encryption:** Migrated to a custom base64 XOR/WebCrypto implementation to bypass browser security blocks on local IPs, backed by native `javax.crypto` AES-GCM for the Android mesh nodes. 

## 🔄 Other Cool Features (from v2.1)

If you haven't used AirChat before, here are some of the things already built-in:

* **Find My Friend (Compass):** Lose your friend in a crowd? Tap their name. AirChat uses GPS and your phone's magnetometer to point a physical compass arrow in their direction, showing the exact distance in meters.
* **Live Battery Status:** You can see the battery percentage of everyone in the chat (pulled natively on Android or via the Battery API on web). You'll know if someone is about to go offline because their phone died.
* **Walkie-Talkie & Voice Notes:** Hold to record audio, swipe left to cancel (complete with a neat particle explosion animation). 
* **BUZZ:** Miss the old Yahoo! Messenger days? You can "Buzz" people. It sends a strong haptic vibration and physically shakes their screen.
* **iMessage-style UI:** Messages group together cleanly, day/night mode adapts to your OS, and standalone emojis are shown larger without the chat bubble.

---

## 🛠️ How it works under the hood

AirChat relies on a dual-architecture so it can talk to anything:

1. **Local Server Mode:** The host runs an embedded web server on Port 8080 and serves HTML/JS/CSS to web clients. Android does it with `NanoHTTPD` + `NanoWSD`; the iOS app has its own HTTP/1.1 + RFC 6455 server on `NWListener`, so both speak one protocol.
2. **Mesh Mode:** Android uses Google Nearby Connections (`P2P_CLUSTER`), iOS uses MultipeerConnectivity (BLE discovery + peer-to-peer Wi-Fi). Devices discover each other via Bluetooth and pass encrypted payloads back and forth, syncing the WebSocket histories. A payload is re-broadcast to every other peer exactly once (deduped by message id), which is what makes the range extension work.
3. **Discovery, iOS edition:** The host also publishes `_airchat-http._tcp` over Bonjour with the short code in a TXT record, so another iPhone can find and join a room without anyone reading out an IP address. The room key is *never* in the TXT record — it only travels inside the URL fragment of the redirect.

---

## 💻 Build it yourself

**Android** — a standard Android Studio project, no weird dependencies:

1. Clone the repo and open it in Android Studio.
2. Let Gradle sync.
3. Hit Run or Build -> Build APK(s).

Requires Android SDK 31+.

**iOS** — Xcode 15+ on macOS, iOS 15.0 minimum, zero third-party dependencies:

1. Open `ios/AirChat/AirChat.xcodeproj`, set your personal team (free Apple ID is fine).
2. Run on a device. The target re-syncs the shared web assets from
   `app/src/main/assets/` as a build phase, so the two apps can't drift apart.
3. No Mac? Enable the bundled workflow once (`git mv ios/ci/ios-ipa.yml .github/workflows/`)
   and GitHub Actions builds `AirChat-unsigned.ipa` for you; sign it with Sideloadly.

Requires nothing else — no CocoaPods, no SPM packages, no entitlements.

---

*Made with ❤️ by SkiDropz*