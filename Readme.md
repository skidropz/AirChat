**SkyChat** este o aplicație de comunicare peer-to-peer care funcționează **fără internet**, transformând un telefon Android într-un server local de chat.

Este soluția perfectă pentru situațiile în care nu există semnal GSM sau Wi-Fi extern (ex: în avion, buncăre, drumeții pe munte sau pene de curent).

## 🌟 De ce SkyChat?

*   ⛔ **Zero Internet:** Funcționează 100% în Airplane Mode (cu Wi-Fi activat).
*   🍎 **Fără instalare pe Client:** Prietenii tăi (cu iPhone, Laptop sau alt Android) **NU** trebuie să instaleze nicio aplicație. Ei folosesc doar browserul (Safari/Chrome).
*   ⚡ **Instantaneu:** Folosește WebSockets pentru o comunicare rapidă, în timp real.
*   🔒 **Privat & Sigur:** Datele nu părăsesc niciodată rețeaua locală creată de telefoane. Nu există cloud, nu există tracking.

## ⚙️ Cum funcționează? (Arhitectura Tehnică)

Aplicația folosește o arhitectură ingenioasă de tip **Server Embedded pe Mobil**:

1.  **Host-ul (Android Server):**

    *   Utilizatorul activează **Hotspot-ul Wi-Fi** local.
    *   Aplicația Android pornește un server web ușor (**NanoHTTPD**) pe portul `8080`.
    *   Aplicația servește fișiere statice (HTML, CSS, JS) către clienți.
    *   Gestionează traficul de mesaje printr-un server **WebSocket** integrat.

2.  **Clientul (Guest):**

    *   Se conectează la rețeaua Wi-Fi emisă de telefonul Host.
    *   Accesează adresa IP a Host-ului (ex: `192.168.43.1:8080`) în browser sau scanând codul QR generat.
    *   Browserul descarcă interfața de chat și stabilește o conexiune persistentă WebSocket.

## 📱 Ghid de Utilizare

### Pasul 1: Pregătirea Serverului (Android)
1.  Instalează APK-ul `SkyChat` pe telefon.
2.  Oprește datele mobile și activează **Hotspot-ul Wi-Fi** (din setările rapide ale telefonului).
3.  Deschide aplicația. Vei vedea un mesaj de genul:
    > "Server pornit la http://192.168.43.1:8080"

### Pasul 2: Conectarea Clientului (iPhone / Alt device)
1.  Activează Wi-Fi și conectează-te la Hotspot-ul creat de telefonul Android.
2.  Deschide orice browser (Safari, Chrome).
3.  Introdu adresa IP afișată pe ecranul serverului (ex: `192.168.43.1:8080`) sau scanează codul QR generat de aplicație.
4.  Scrie-ți numele și apasă **Conectare**.

### Pasul 3: Chat!
*   Scrie mesaje. Ele vor apărea instantaneu pe toate dispozitivele conectate.

## 🛠️ Tech Stack

*   **Android (Native):** Kotlin
*   **Server Engine:** NanoHTTPD + NanoWSD (WebSockets)
*   **Frontend:** Vanilla JavaScript, HTML5, CSS3 (Mobile-first design)
*   **Network Utils:** Detectare inteligentă a IP-ului pe interfețele de rețea.
---
Made with ❤️ by SkiDropz