# 📡 AirChat

**AirChat** este o aplicație de comunicare peer-to-peer avansată, care funcționează **fără internet**, transformând un telefon Android într-un nod central de comunicații.

Este soluția pentru situațiile de criză, drumeții în zone izolate sau aglomerații urbane unde rețelele GSM sunt absente.

## 🌟 De ce AirChat?

⛔ **Zero Internet:** Funcționează 100% în Airplane Mode sau în zonele fără semnal GSM/4G/5G.

🍎 **Universal:** Prietenii tăi cu iPhone, Laptop sau tablete **NU** trebuie să instaleze nicio aplicație. Ei se conectează la tine folosind doar browserul (Safari/Chrome).

🕸️ **Mesh Networking:** Telefoanele Android se pot descoperi și conecta între ele automat, extinzând raza de acțiune a rețelei.

⚡ **Real-Time:** Folosește WebSockets pentru o comunicare instantanee și fluidă.

🔒 **Privacy First:** Datele nu părăsesc niciodată rețeaua locală creată de telefoane. Nu există cloud, nu există tracking, nu există baze de date externe.

## 📸 Screenshots

<p float="left">
<img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20principala%CC%86.png" alt="Interfața principală" width="300">
    <img src="https://github.com/skidropz/AirChat/blob/main/Codul%20QR.png" alt="Codul QR" width="300">
<img src="https://github.com/skidropz/AirChat/blob/main/Chat.png" alt="Chat" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Lista%CC%86%20utilizatori%20conectat%CC%A6i.png" alt="Listă useri activi" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%20din%20browser.png" alt="Interfața din browser" width="300">
  <img src="https://github.com/skidropz/AirChat/blob/main/Interfat%CC%A6a%CC%86%20Mesh.png" alt="Interfață Mesh" width="300">
</p>

---

## 🧠 Cum funcționează?

AirChat folosește o arhitectură duală unică pentru a maximiza compatibilitatea și raza de acțiune:

### 1. Modul Server Local (HTTP + WebSockets)
Telefonul tău Android pornește un **Web Server** minuscul.
*   Orice dispozitiv (iPhone, PC, etc.) conectat la Hotspot-ul tău poate accesa interfața de chat prin browser, scanând un cod QR.
*   Telefonul tău devine "camera de chat" pentru toți cei din jur.

### 2. Modul Mesh (Google Nearby Connections)
Telefoanele Android cu AirChat instalat pot comunica **direct** între ele, fără a fi nevoie să se conecteze la același Hotspot.
*   **Descoperire Automată:** Aplicația scanează în fundal folosind Bluetooth Low Energy (BLE).
*   **Feedback Vizual:** Când un alt server AirChat este detectat în proximitate, butonul de conectare începe să **pulseze lent** (Albastru <-> Negru), iar textul se schimbă în *"Conectare în Mesh"*.
*   **Bridging:** Mesajele primite de la un iPhone conectat prin Wi-Fi sunt preluate de telefonul Android și retransmise prin Mesh către alte telefoane Android din apropiere.

---

## 📱 Ghid de Utilizare

### Scenariul A: Ești "Host" pentru prieteni cu iPhone/Laptop

1.  Oprește datele mobile și activează **hotspot-ul**.
2.  Deschide aplicația AirChat. Vei vedea un cod QR generat automat.
3.  Prietenii tăi se conectează la hotspot-ul tău.
4.  Ei scanează codul QR cu camera telefonului sau introduc IP-ul (ex: `192.168.43.1:8080`) în browser.
5.  Browserul va da eroare de securitate dar conversațiile sunt criptate end-to-end.

### Scenariul B: Conectare Mesh (Android <-> Android)

1.  Tu și un prieten aveți amândoi AirChat instalat pe Android. Unul dintre voi trebuie să fie host-ul (deja conectat în aplicație).
2.  Nu este nevoie de hotspot comun. Doar asigurați-vă că bluetooth-ul și locația sunt pornite.
3.  Apropiați-vă unul de celălalt.
4.  **Urmăriți butonul de login:** Când telefoanele se "văd", butonul va începe să **pulseze** și va apărea o notificare de sistem: *"Server AirChat Detectat. Dorești să te conectezi?"*.
5.  Apăsați pe buton sau pe notificare și confirmați conexiunea. Acum sunteți conectați direct prin unde radio.

---

## 🛠️ Compilare și Instalare

Dacă dorești să modifici codul sursă sau să compilezi aplicația singur:

1.  **Importă Proiectul:** Mergi la `File -> New -> Project from Version Control...` și lipește link-ul de GitHub.
2.  **Sincronizare Gradle:** Așteaptă ca Android Studio să descarce dependențele.
3.  **Permisiuni:** Asigură-te că emulatorul sau telefonul are Developer Mode activat.
4.  **Build:** Mergi la `Build -> Build Bundle(s) / APK(s) -> Build APK(s)`.
5.  **Instalare:** Fișierul `app-debug.apk` va fi generat în folderul `build/outputs/apk/debug`.

## 💻 Tech Stack

*   **Limbaj:** Kotlin (Android Native)
*   **Mesh Networking:** Google Nearby Connections API (Strategy: P2P_CLUSTER)
*   **Server Web:** NanoHTTPD (Embedded HTTP Server)
*   **Real-time Comms:** NanoWSD (WebSocket Daemon)
*   **Frontend:** HTML5, CSS3 (iOS Dark Mode Style), Vanilla JavaScript
*   **UI Feedback:** CSS Animations controlate prin JavaScript Injection din Kotlin.

---

Made with ❤️ by SkiDropz
