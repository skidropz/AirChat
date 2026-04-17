# 📡 AirChat

AirChat is an offline, peer-to-peer messaging app built for Android. It basically turns your phone into a portable communication hub that works completely without the internet. 

I originally built this for situations where networks are either dead or completely overloaded—think hiking in the mountains, packed music festivals, protests, or power outages.

---

### Why use AirChat?

The coolest part about AirChat is that **only one person needs to have the app installed**. 

If you have the app on your Android phone, your friends on iPhones, laptops, or older devices don't need to download anything. They just connect to your phone's Wi-Fi hotspot, and a "Captive Portal" pops up (just like when you connect to hotel Wi-Fi). It drops them right into the chat via their browser. 

* **100% Offline:** Works in Airplane Mode or in the middle of nowhere.
* **Viral App Sharing:** If your friend *does* want the native Android app but has no internet to get it from the Play Store, AirChat actually hosts its own `.apk`. They can download it directly from your hotspot.
* **Hybrid Mesh Networking:** If multiple people have the Android app, the phones will find each other via Bluetooth and form a mesh network. This extends the range—Phone A can talk to Phone C by bouncing the signal through Phone B.
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

1. **Local Server Mode:** The Android host runs an embedded web server (`NanoHTTPD` + `NanoWSD` for WebSockets on Port 8080). It serves HTML/JS/CSS to web clients.
2. **Mesh Mode:** It uses the Google Nearby Connections API (`P2P_CLUSTER` strategy). Android devices discover each other via BLE/Bluetooth and pass encrypted payloads back and forth, syncing the WebSocket histories.

---

## 💻 Build it yourself

It's a standard Android Studio project. No weird dependencies.

1. Clone the repo and open it in Android Studio.
2. Let Gradle sync.
3. Hit Run or Build -> Build APK(s).

Requires Android SDK 31+.

---

*Made with ❤️ by SkiDropz*