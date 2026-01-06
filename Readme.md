# 📡 AirChat

**AirChat** este o aplicație românească de comunicare **peer-to-peer**, care funcționează **fără internet**, transformând un telefon Android într-un **hub de comunicații locale și Mesh**.

Este soluția ideală pentru situații de criză, drumeții în zone izolate, festivaluri, proteste sau aglomerații urbane unde rețelele sunt indisponibile sau suprasolicitate.

---

## De ce AirChat?

⛔ **Zero Internet**
Funcționează 100% în **Airplane Mode** sau în zone fără orice fel de semnal.

🍎 **Universal**
Prietenii tăi cu **iPhone, laptop sau tabletă** NU trebuie să instaleze nicio aplicație. Se conectează direct din browser (Safari / Chrome).

🕸️ **Hybrid Mesh Networking**
Telefoanele Android se descoperă automat între ele prin Bluetooth și formează o rețea Mesh, extinzând raza de acțiune.

🎙️ **Walkie-Talkie & Survival**
Include mesaje vocale, busolă pentru localizarea prietenilor și alerte haptice, precum cea pentru buzz.

⚡ **Real-Time Communication**
Mesaje instant folosind **WebSockets**, cu sincronizare bidirecțională Mesh ↔ Web.

🔒 **Privacy-First**
Fără cloud, fără conturi, fără tracking. Datele **nu părăsesc niciodată rețeaua locală**!

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

## 🚀 Noutăți în v2.0

### 🎙️ Audio & Walkie-Talkie
*   **Hold-to-Record:** Ține apăsat microfonul pentru a înregistra și trimite instant mesaje vocale.
*   **Audio Player Custom:** Interfață stil WhatsApp cu **waveform generat dinamic** pe baza frecvențelor sonore.
*   **Swipe-to-Cancel:** Glisare stânga pentru anulare, cu efecte vizuale de **particule (scântei)** și explozie la anulare.

### 🧭 Find My Friend
*   **Busolă Offline:** Localizează alți utilizatori din rețea fără hărți sau internet.
*   **GPS Tracking:** Afișează distanța exactă (metri) și o săgeată direcțională către partenerul de chat.
*   **Funcția BUZZ ⚡:** Trimite o vibrație haptică puternică și scutură ecranul participanților din chat (Yahoo! Messenger style).

### 🕸️ Mesh Networking (Hybrid Mode)
*   **Android-to-Android Discovery** prin **Google Nearby Connections**.
*   **Smart Bridging:** Mesajele sunt retransmise automat între Mesh și clienții Web.
*   **Feedback Vizual:** Butonul de conectare pulsează *(Albastru ↔ Negru)* la detectarea unui nod.

### 📷 Media & Chat
*   **Trimitere imagini** (doar din galerie) cu compresie automată și **Fullscreen Viewer**.
*   **Swipe-to-Reply** cu scroll automat la mesajul original.
*   **Message History:** Sincronizare automată a ultimelor 50 de mesaje.
*   **Smart Seen Status:** "Văzut de..." bazat pe **Page Visibility API** (doar când utilizatorul este activ).

---

## 🎨 UI / UX Modern

*   **iOS Dark Mode Theme** (Blur, culori Apple, font San Francisco-style).
*   **Interactive UI**:
    *   **Sparklers:** Particule strălucitoare care urmăresc degetul la înregistrare.
    *   **Culori Dinamice:** Butonul de conectare preia culoarea aleasă de utilizator.
    *   **Animații fluide:** Pop-in, Slide-up, Fade-in.
*   **Listă utilizatori activi** cu contor live.

---

## Cum funcționează AirChat?

AirChat folosește o **arhitectură duală hibridă** pentru compatibilitate maximă.

### 1️⃣ Modul Server Local (HTTP + WebSockets)
Telefonul Android pornește un **server web embedded**:
*   Dispozitivele (iPhone/PC/Android) conectate la hotspot accesează chat-ul din browser.
*   Conectare rapidă prin **QR Code**.

### 2️⃣ Modul Mesh (Android ↔ Android)
*   Conectare directă prin **Bluetooth / BLE**.
*   Nu necesită Wi-Fi comun.
*   Extinde raza de acțiune a rețelei (Telefon A <-> Telefon B <-> iPhone C).

---

## 📱 Ghid de Utilizare

### Scenariul A — Host pentru iPhone / Laptop / Android
1.  Dezactivează datele mobile și activează **Hotspot**.
2.  Deschide AirChat (QR generat automat).
3.  Prietenii se conectează la hotspot și scanează QR-ul.

### Scenariul B — Drumeție / Mesh (Android ↔ Android)
1.  Ambele telefoane au AirChat instalat.
2.  Bluetooth și locația (GPS) sunt pornite.
3.  Apropiați telefoanele. Butonul pulsează → **"Conectare în Mesh"**.
4.  Dacă vă pierdeți, apăsați pe numele utilizatorului în listă pentru a deschide **busola**.

---

## 🛠️ Detalii Tehnice

*   **Limbaj:** Kotlin (Android Native)
*   **Server:** NanoHTTPD + NanoWSD (Port 8080, Protocol HTTP).
*   **Frontend:** HTML5, CSS3, Vanilla JS.
*   **Audio:** Web Audio API & MediaRecorder (Base64 encoding).
*   **Senzori:** SensorManager (Magnetometru + Accelerometru) & LocationManager (GPS).
*   **Securitate:** HTTP simplu (fără erori SSL pe LAN), datele sunt volatile (RAM only).

---

## 🛠️ Compilare & Instalare

1.  Importă proiectul în Android Studio.
2.  Sincronizează Gradle.
3.  `Build → Build APK(s)`.
4.  APK-ul se găsește în `build/outputs/apk/debug`.

---

**Made with ❤️ by SkiDropz**
