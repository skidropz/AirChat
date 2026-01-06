
# AirChat

**AirChat** este o aplicație avansată de comunicare **peer-to-peer**, care funcționează **fără internet**, transformând un telefon Android într-un **hub de comunicații locale și Mesh**.

Este soluția ideală pentru situații de criză, drumeții în zone izolate, festivaluri, proteste sau aglomerații urbane unde rețelele GSM/4G/5G sunt indisponibile sau suprasolicitate.

---

## De ce AirChat?

⛔ **Zero Internet**
Funcționează 100% în **Airplane Mode** sau în zone fără semnal mobil.

🍎 **Universal**
Prietenii tăi cu **iPhone, laptop sau tabletă** NU trebuie să instaleze nicio aplicație — se conectează direct din browser (Safari / Chrome).

🕸️ **Hybrid Mesh Networking**
Telefoanele Android se descoperă automat între ele și formează o rețea Mesh, extinzând raza de acțiune.

⚡ **Real-Time Communication**
Mesaje instant folosind **WebSockets**, cu sincronizare bidirecțională Mesh ↔ Web.

🔒 **Privacy-First**
Fără cloud, fără conturi, fără tracking. Datele **nu părăsesc niciodată rețeaua locală**.

---

## 📸 Screenshots

<p float="left">
<img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20principala%CC%86.png" alt="Interfața principală" width="300">
    <img src="https://github.com/skidropz/AirChat/blob/main/Chatul.png" alt="Codul QR" width="300">
<img src="https://github.com/skidropz/AirChat/blob/main/Codul%20QR.png" alt="Chat" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20din%20browser.png" alt="Listă useri activi" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Lista%CC%86%20utilizatori.png" alt="Interfața din browser" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%CC%86%20Mesh.png" alt="Interfață Mesh" width="300">
</p>

---

## 🚀 Noutăți în v2.0 — *“Mesh & Media Update”*

### 🕸️ Mesh Networking (Hybrid Mode)

* **Android-to-Android Discovery** prin **Google Nearby Connections**
* **Fără hotspot comun** necesar între telefoane Android
* **Smart Bridging**:

  * Mesajele primite din Mesh sunt retransmise automat către clienții Web
  * Mesajele din Web ajung în Mesh
 
* **Feedback Vizual Dinamic**:

  * Butonul de conectare pulsează *(Albastru ↔ Negru)*
  * Textul se schimbă în **„Conectare în Mesh”** când un nod este detectat

---

### 📷 Media Sharing

* Trimitere imagini direct din **galerie sau cameră**
* **Compresie JPEG automată (client-side)** pentru transfer rapid
* **Fullscreen Image Viewer** cu animație de zoom (stil iOS)

---

### 💬 Chat Experience

* **Swipe-to-Reply** (glisare dreapta pe mesaj)
* **Context vizual** pentru reply-uri
* **Scroll-to-Target** cu highlight temporar la mesajul original

* **Message History**:

  * Ultimele **50 de mesaje** sunt salvate pe server
  * Sincronizare automată pentru utilizatorii care se conectează mai târziu
 
* **Seen Status Avansat**:

  * „Văzut de…”
  * Folosește **Page Visibility API** (mesajele sunt marcate ca văzute doar când utilizatorul este activ)

---

### 👥 User Management

* **Listă utilizatori activi** (modal popup)
* **Contor live**: „X online”
* **Disconnect Button** pentru resetarea sigură a sesiunii WebSocket

---

## 🎨 UI / UX

* **iOS Dark Mode Theme** (culori Apple, blur, font San Francisco-style)
* **UI Dinamic**:

  * Butonul de conectare își schimbă culoarea în funcție de tema aleasă
  * Culori chat: Blue, Red, Green, Purple, Orange, White
 
* **Animații fluide**:

  * Mesaje (`slideUp`, `popIn`)
  * Modale (`fadeIn`, `scaleUp`)
 
* **SVG Icons** curate (înlocuirea emoji-urilor)

---

## Cum funcționează AirChat?

AirChat folosește o **arhitectură duală hibridă** pentru compatibilitate maximă.

### 1️⃣ Modul Server Local (HTTP + WebSockets)

Telefonul Android pornește un **server web embedded**:

* Dispozitivele conectate la hotspot accesează chat-ul din browser
* Conectare rapidă prin **QR Code**
* Telefonul devine „camera de chat” locală

### 2️⃣ Modul Mesh (Android ↔ Android)

* Conectare directă prin **Google Nearby Connections**
* Descoperire automată prin BLE
* Fără Wi-Fi comun
* Mesajele sunt **bridged** între Mesh și Web

---

## 📱 Ghid de Utilizare

### Scenariul A — Host pentru iPhone / Laptop

1. Dezactivează datele mobile
2. Activează **Hotspot**
3. Deschide AirChat (QR generat automat)
4. Prietenii se conectează la hotspot
5. Scanează QR sau accesează adresa IP afișată `exemplu: 192.168.43.1:8080`

---

### Scenariul B — Conectare Mesh (Android ↔ Android)

1. Ambele telefoane au AirChat instalat
2. Bluetooth și locația sunt pornite
3. Apropiați telefoanele
4. Butonul începe să pulseze → **Conectare în Mesh**
5. Confirmați conexiunea

---

## 🧪 Cum testezi Mesh Networking?

1. Două telefoane Android fizice
2. Bluetooth + Locație active
3. Apropiere fizică
4. Apasă **"Conectare în Mesh”**

---

## 🛠️ Backend & Technical Details

* **Protocol:** HTTP simplu (port 8080)
* Elimină problemele cu certificate self-signed

* **WebView Fixes**:

  * `onShowFileChooser` pentru upload poze
  * `clearCache` la pornire
 
* **Mesaje**:

  * ID unic (`timestamp + random`)
  * Gestionare reply & seen status corectă

---

## 💻 Tech Stack

* **Android:** Kotlin
* **Mesh:** Google Nearby Connections (P2P_CLUSTER)
* **Server:** NanoHTTPD
* **WebSockets:** NanoWSD
* **Frontend:** HTML5, CSS3 (iOS Dark Mode), Vanilla JS
* **Animations:** CSS + JS injectat din Kotlin

---

## 🛠️ Compilare & Instalare

1. Import proiectul din GitHub în Android Studio
2. Așteaptă sincronizarea Gradle
3. Activează Developer Mode pe device
4. `Build → Build APK(s)`
5. APK-ul se găsește în `build/outputs/apk/debug`

---

**Made with ❤️ by SkiDropz**

