# 📡 AirChat

AirChat is a Romanian peer-to-peer communication app that works without internet, turning an Android phone into a local and Mesh communication hub.

It is the ideal solution for crisis situations, hiking in remote areas, festivals, protests, or crowded urban environments where networks are unavailable or overloaded.

---

# Why AirChat?

**⛔ Zero Internet**

Works 100% in Airplane Mode or in areas without any signal.

**🍎 Universal**

Your friends with an iPhone, laptop, or tablet DO NOT have to install any application. They connect directly from their browser (Safari / Chrome).

**🕸️ Hybrid Mesh Networking**

Android phones automatically discover each other via Bluetooth and form a Mesh network, extending the communication range.

**🎙️ Walkie-Talkie & Survival**

Includes voice messages, a compass for locating friends, and haptic alerts, such as the buzz feature.

**⚡ Real-Time Communication**

Instant messaging using WebSockets, with bidirectional Mesh ↔ Web synchronization.

**🔒 Privacy-First**

No cloud, no accounts, no tracking. Data never leaves the local network!

---

## 📸 Screenshots

<p float="left">
<img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20principala%CC%86.png" alt="Interfața principală" width="300">
    <img src="https://github.com/skidropz/AirChat/blob/main/Chatul.png" alt="Codul QR" width="300">
<img src="https://github.com/skidropz/AirChat/blob/main/Codul%20QR.png" alt="Chat" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20din%20browser.png" alt="Listă useri activi" width="300">
      <img src="https://github.com/skidropz/AirChat/blob/main/Chatul%20din%20browser.png" alt="Listă useri activi" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Lista%CC%86%20utilizatori.png" alt="Interfața din browser" width="300">
    <img src="https://github.com/skidropz/AirChat/blob/main/Ga%CC%86sire%20prieteni.png" alt="Interfața din browser" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%CC%86%20Mesh.png" alt="Interfață Mesh" width="300">
</p>

---

## 🚀 What's New in v2.0

### 🎙️ Audio & Walkie-Talkie

**Hold-to-Record**

Hold down the microphone to record and instantly send voice messages.

**Custom Audio Player**

WhatsApp-style interface with a dynamically generated waveform based on sound frequencies.

**Swipe-to-Cancel**

Swipe left to cancel, featuring particle visual effects (sparks) and an explosion animation upon cancellation.


### 🧭 Find My Friend

**Offline Compass**

Locate other network users without maps or internet.

**GPS Tracking**

Displays the exact distance (in meters) and a directional arrow pointing to your chat partner.

**BUZZ Feature**

Sends a strong haptic vibration and shakes the screen for chat participants (Yahoo! Messenger style).


### 🕸️ Mesh Networking (Hybrid Mode)

Android-to-Android Discovery via Google Nearby Connections.

Messages are automatically relayed between the Mesh and Web clients.

The connect button pulses (Blue ↔ Black) when a node is detected.


### 📷 Media & Chat

Image Sharing (from gallery only) with automatic compression and a Fullscreen Viewer.

Swipe-to-Reply with automatic scrolling to the original message.

Automatic synchronization of the last 50 messages.

Smart Seen Status: "Seen by..." indicator based on the Page Visibility API (active only when the user is looking at the page).

---

## 🎨 Modern UI / UX

iOS Dark Mode Theme (Blur effects, Apple color palette, San Francisco-style font).

**Interactive UI:**

Glowing particles that follow your finger while recording audio.

The connect button adopts the user's chosen profile color.

Fluid Animations: Pop-in, Slide-up, Fade-in.

Active User List with a live counter.

---

## How does AirChat work?

AirChat uses a dual hybrid architecture for maximum compatibility.

### 1️⃣ Local Server Mode (HTTP + WebSockets)

The Android phone starts an embedded web server.

Devices (iPhone/PC/Android) connected to the hotspot access the chat via their browser.

Quick login using a QR Code.


### 2️⃣ Mesh Mode (Android ↔ Android)

Direct connection via Bluetooth / BLE.

Does not require a shared Wi-Fi network.

Extends the network's range (Phone A <-> Phone B <-> iPhone C).

---

## 📱 User Guide

### Scenario A — Host for iPhone / Laptop / Android

Disable mobile data and enable Hotspot.

Open AirChat (QR code is generated automatically).

Friends connect to the hotspot and scan the QR code.


### Scenario B — Hiking / Mesh (Android ↔ Android)

Both phones have AirChat installed.

Bluetooth and Location services (GPS) are turned on.

Bring the phones close together. The connect button will pulse → "Connecting to Mesh".

If you get separated, tap on a user's name in the list to open the compass.

---

## 🛠️ Technical Details

**Language:** Kotlin (Android Native)

**Server:** NanoHTTPD + NanoWSD (Port 8080, HTTP Protocol).

**Frontend:** HTML5, CSS3, Vanilla JS.

**Audio:** Web Audio API & MediaRecorder (Base64 encoding).

**Sensors:** SensorManager (Magnetometer + Accelerometer) & LocationManager (GPS).

**Security:** Plain HTTP (no SSL errors on LAN), data is volatile (RAM only).

---

## 🛠️ Build & Install

Import the project into Android Studio.

Sync Gradle.

Build → Build APK(s).

The APK will be located in build/outputs/apk/debug.

---

**Made with ❤️ by SkiDropz**
