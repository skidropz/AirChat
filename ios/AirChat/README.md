# 📡 AirChat — iOS (nativ, SwiftUI)

Aceasta este rescrierea **nativă** a aplicației AirChat (original Android/Kotlin) pentru iOS,
în **SwiftUI**, păstrând protocolul de mesaje și criptarea E2EE, astfel încât să fie
**interoperabilă** cu clientul web (browser) și, parțial, cu nodurile Android.

> ⚠️ **Limitare fundamentală iOS**: iOS **nu permite** unei aplicații să creeze un hotspot Wi-Fi
> sau să declanșeze un „Captive Portal" (feature-ul definitoriu din varianta Android, unde doar
> unul are aplicația și restul intră prin hotspot). Pe iOS, „host mode" rulează un **server web
> local** accesibil doar celor aflați pe **aceeași rețea Wi-Fi**. Oaspeții deschid link-ul /
> scanează QR-ul în browser.

---

## ✅ Ce este portat

| Funcție Android | Corespondent iOS | Status |
|---|---|---|
| `NanoHTTPD` + `NanoWSD` (server HTTP/WebSocket pe port 8080) | `AirChatServer` pe `Network` framework (fără dependențe) | ✅ |
| Client web (HTML/JS/CSS) servit browser-elor | Asset-ele web originale, servite identic | ✅ |
| Captive portal / short-code / redirect | Redirecturi HTTP pentru probe de conectivitate + cod scurt | ✅ (fără captive portal real) |
| Criptare XOR + base64 (web, E2EE) | `XORCipher` — reproducere bit-cu-bit a `app.js` | ✅ |
| AES-GCM (mesh Android) | `MeshCrypto` cu `CryptoKit` (același format IV+ct+tag) | ✅ |
| Google Nearby Connections (mesh) | `MultipeerConnectivity` (mesh **iOS ↔ iOS**) | ✅ |
| QR code (ZXing) | `CoreImage` (`CIQRCodeGenerator`) | ✅ |
| Senzori: GPS + busolă + baterie | `CoreLocation`, `CLHeading`, `UIDevice` | ✅ |
| Find My Friend (busolă) | `CompassSheet` cu `bearingDegrees`/`distanceMetres` (Haversine) | ✅ |
| Mesaje vocale (walkie-talkie) | `VoiceRecorder` cu `AVAudioRecorder` | ✅ |
| Buzz (vibrație + shake) | `UIImpactFeedbackGenerator` + animație shake | ✅ |
| Chat privat 1-la-1 | Rutare pe `recipient`, UI de conversație privată | ✅ |
| „Seen by", reply, imagini, emoji-only | Toate portate în `MessageRow` | ✅ |
| Distribuire APK viral (`/download-app`) | Pagină informativă (iOS nu poate distribui binar) | ⚠️ limitat |

### Interoperabilitate
- **iOS host ↔ browser**: complet interoperabil (același protocol XOR + WebSocket).
- **iOS ↔ iOS (mesh)**: complet, via `MultipeerConnectivity` + AES-GCM.
- **iOS ↔ Android mesh**: ❌ nu interoperabil (Nearby Connections ≠ MultipeerConnectivity);
  dar comunică prin serverul web comun dacă ambele sunt pe același Wi-Fi.

---

## 🏗️ Arhitectură

```
AirChat/
├── App/            AirChatApp.swift      – @main, RootView, generare cheie de cameră
├── Core/           AppConstants, ChatStore (hub central: protocol + transport + UI state)
├── Models/         AirChatMessage        – modelul wire-format (JSON identic cu app.js)
├── Crypto/         XORCipher, MeshCrypto – E2EE (XOR/base64 + AES-GCM)
├── Networking/     AirChatServer (HTTP+WS), HTTPRequest, WebSocketFrame,
│                   ClientConnection, WebSocketClient (join)
├── Mesh/           MeshManager           – MultipeerConnectivity
├── Sensors/        LocationManager, DeviceSensors (baterie, buzz)
├── UI/             StartView, HostSetupView, JoinView, ChatView, MessageRow,
│                   ComposerBar, UsersSheet, CompassSheet, Theme, Components
└── Resources/      Info.plist, Assets.xcassets, Web/ (client web), *.lproj
```

**Fluxul de mesaje** (hub-ul `ChatStore`):
- UI nativ trimite → `ChatStore.sendOutgoing` → `encode` (XOR wrap) →
  `server.broadcastToAll` (browsere + istoric) + `mesh.send` (peers AES).
- Browser trimite → `AirChatServer` (echo la toate browserele) →
  `ChatStore.fromWeb` → decodare XOR + afișare UI + `mesh.send`.
- Peer mesh trimite → `MeshManager` (AES decrypt + dedup) →
  `ChatStore.fromMesh` → afișare UI + `server.broadcastToAll`.

---

## 🛠️ Build

Necesită **Xcode 15+** (iOS 17 SDK) și un Mac.

1. Deschide `AirChat.xcodeproj` în Xcode.
2. Selectează un *development team* în **Signing & Capabilities** (sau lasă pe
   „Sign to Run Locally" pentru testare pe propriul device).
3. Selectează un simulator iPhone sau device-ul conectat → **Run** (⌘R).

Regenerarea fișierului de proiect (dacă adaugi/ștergi fișiere):
```bash
python3 generate_project.py
```

### Permisiuni (solicitate automat)
- **Microfon** – mesaje vocale
- **Locație (When In Use)** – busola „Find My Friend"
- **Fotografii / Cameră** – atașare imagini (`PhotosPicker`)
- **Rețea locală** – server host + mesh (Bonjour `_airchat-mesh._tcp`)

> `NSAppTransportSecurity` are `NSAllowsArbitraryLoads = true` pentru că aplicația
> comunică peste HTTP/WS cu IP-uri locale (LAN). Necesar pentru funcționare offline.

---

## 🧪 Testare rapidă

1. **Host**: lansează pe un iPhone conectat la Wi-Fi → alege „Host a room". Notează
   `http://<IP>:8080/<COD>` și/sau QR-ul.
2. **Client web**: de pe un laptop/alt telefon **pe același Wi-Fi**, deschide link-ul
   sau scanează QR-ul → intră cu un nume → trimite mesaje. Vor apărea live în UI-ul nativ.
3. **Mesh**: lansează aplicația pe un al doilea iPhone → Host → vor descoperi automat
   (Bonjour) și vor forma mesh-ul iOS.
4. **Join**: un al doilea iPhone alege „Join a room" → lipește link-ul → conectare WS.

---

## 🐞 Known limitations / TODO

- `RootView` folosește un `switch` pe stare (nu `NavigationLink`); din chat nu ai buton
  înapoi la ecranul de host info — repornește aplicația pentru a revedea QR/IP.
- Mesh auto-conectează toate dispozitivele găsite (fără prompt de confirmare).
- Bateria proprie pe simulator e mereu 100% (`UIDevice.batteryLevel == -1`).
- Emojis mari („standalone emoji"): suport de bază.
- Către App Store va trebui adăugat un `AppIcon` real (1024×1024) în `Assets.xcassets`.

---

*Port Swift/SwiftUI al AirChat de SkiDropz.*
