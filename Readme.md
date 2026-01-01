**SkyChat** este o aplicație de comunicare peer-to-peer care funcționează **fără internet**, transformând un telefon Android într-un server local de chat.

Este soluția perfectă pentru situațiile în care nu există semnal GSM sau Wi-Fi extern (ex: în avion, buncăre, drumeții pe munte sau pene de curent).

## 🌟 De ce SkyChat?

*   ⛔ Funcționează 100% în Airplane Mode (cu Wi-Fi activat).
*   🍎 Prietenii tăi (cu iPhone, Laptop sau alt Android) **NU** trebuie să instaleze nicio aplicație. Ei folosesc doar browserul (Safari/Chrome).
*   ⚡ Folosește WebSockets pentru o comunicare rapidă, în timp real.
*   🔒 Datele nu părăsesc niciodată rețeaua locală creată de telefoane. Nu există cloud, nu există tracking.

## 📱 Ghid de Utilizare

### Pasul 1: Pregătirea Serverului (Android)

1.  Instalează APK-ul `SkyChat` pe telefon. Click [aici](https://github.com/skidropz/SkyChat/releases/download/Release/SkyChat_v1.0.apk) ca să descarci versiunea compilată.
2.  Oprește datele mobile și activează **Hotspot-ul Wi-Fi** (din setările telefonului.
3.  Deschide aplicația. Vei vedea un mesaj de genul și un cod QR în dreapta:
    > "Server pornit la http://192.168.43.1:8080"

### Pasul 2: Conectarea Clientului (iPhone / Alt device)

1.  Conectează-te la hotspot-ul telefonului.
2.  Deschide orice browser (Safari, Chrome).
3.  Introdu adresa IP afișată pe ecranul serverului (ex: `192.168.43.1:8080`) sau scanează codul QR generat de aplicație.
4.  Scrie-ți numele și apasă **Conectare**.

### Pasul 3: Chat!
*   Mesajele vor apărea instantaneu pe toate dispozitivele conectate.

### Pentru compilare:

1.   Importă Proiectul: Mergi la File -> New -> Project from Version Control... și lipește link-ul de GitHub.
2.   Sincronizează Gradle: Așteaptă ca bara de progres de jos ("Gradle Build") să se termine. Dacă apar erori, apasă pe link-urile albastre de instalare care apar în consolă.
3.   Compilează (Build): Mergi în meniul de sus la Build -> Build Bundle(s) / APK(s) -> Build APK(s).
4.   Localizează fișierul: Când apare notificarea în colțul din dreapta jos, apasă pe locate. Vei găsi fișierul app-debug.apk gata de instalat pe telefon.

## 🛠️ Tech Stack

*   **Android (Native):** Kotlin
*   **Server Engine:** NanoHTTPD + NanoWSD (WebSockets)
*   **Frontend:** Vanilla JavaScript, HTML5, CSS3 (Mobile-first design)
*   **Network Utils:** Detectare inteligentă a IP-ului pe interfețele de rețea.
---
Made with ❤️ by SkiDropz
