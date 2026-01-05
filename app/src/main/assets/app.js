// 1. Configurare Protocol și URL
const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
const WS_URL = protocol + window.location.host;

// 2. Variabile de Stare
let socket;
let myName = "";
let heartbeatInterval;
let isLoggedIn = false;
let pendingLogin = false;
let myBubbleColor = "blue"; // Culoarea selectată
let colorLocked = false;

// 3. Elemente DOM
const loginScreen = document.getElementById('login-screen');
const chatScreen = document.getElementById('chat-screen');
const msgList = document.getElementById('messages-list');
const msgInput = document.getElementById('msg-input');
const statusDot = document.getElementById('status-dot');
const onlineCountEl = document.getElementById('online-count');
const colorPicker = document.querySelector('.color-picker');

// 4. Logica Selector Culori
document.querySelectorAll('.color-option').forEach(option => {
    option.addEventListener('click', () => {
        if (colorLocked) return;

        document.querySelectorAll('.color-option')
            .forEach(o => o.classList.remove('selected'));

        option.classList.add('selected');
        myBubbleColor = option.dataset.color;
    });
});

// 5. Logica de Login
function login() {
    const input = document.getElementById('username-input');
    const name = input.value.trim();

    if (!name) {
        alert("Te rugăm să introduci un nume!");
        return;
    }

    myName = name; // Salvăm numele utilizatorului curent

    if (socket && socket.readyState === WebSocket.OPEN) {
        completeLogin();
    } else {
        pendingLogin = true;
        renderSystemMessage("Se conectează la server...");
        // Dacă socket-ul e închis, încercăm să-l reconectăm
        if (!socket || socket.readyState === WebSocket.CLOSED) {
            connectServer();
        }
    }
}

function completeLogin() {
    if (isLoggedIn) return;
    isLoggedIn = true;
    pendingLogin = false;

    // Blocăm schimbarea culorii
    colorLocked = true;
    if (colorPicker) colorPicker.style.display = "none";

    // Schimbăm ecranele
    loginScreen.classList.add('hidden');
    chatScreen.classList.remove('hidden');
    statusDot.classList.add('connected');

    // Anunțăm intrarea pe server
    sendPayload({ type: 'system', text: `${myName} s-a conectat.` });
    startHeartbeat();
}

// 6. Conexiunea WebSocket
function connectServer() {
    socket = new WebSocket(WS_URL);

    socket.onopen = () => {
        console.log("Conectat la AirChat Server");
        statusDot.classList.add('connected');

        if (myName && (pendingLogin || !isLoggedIn)) {
            completeLogin();
        }
    };

    socket.onmessage = (event) => {
        if (event.data === "ping") return;

        try {
            const data = JSON.parse(event.data);
            handleData(data);
        } catch (e) {
            console.error("Eroare parsare mesaj JSON", e);
        }
    };

    socket.onclose = () => {
        statusDot.classList.remove('connected');
        renderSystemMessage("⚠️ Conexiune pierdută.");
        stopHeartbeat();
        isLoggedIn = false;
        // Încercare de reconectare automată după 3 secunde
        setTimeout(connectServer, 3000);
    };

    socket.onerror = (err) => console.error("Eroare Socket:", err);
}

// 7. Heartbeat (Puls pentru a menține conexiunea activă)
function startHeartbeat() {
    stopHeartbeat();
    heartbeatInterval = setInterval(() => {
        if (socket && socket.readyState === WebSocket.OPEN) {
            socket.send("ping");
        }
    }, 10000);
}

function stopHeartbeat() {
    if (heartbeatInterval) {
        clearInterval(heartbeatInterval);
        heartbeatInterval = null;
    }
}

// 8. Trimitere Mesaje
function sendPayload(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        data.sender = myName;
        data.color = myBubbleColor;
        socket.send(JSON.stringify(data));
    } else {
        console.warn("Nu se poate trimite: Socket-ul nu este deschis.");
    }
}

function sendMessage() {
    const text = msgInput.value.trim();
    if (!text) return;

    sendPayload({ type: 'chat', text: text });
    msgInput.value = "";
    msgInput.focus();
}

// 9. Gestionare Date Primite
async function handleData(data) {
    switch (data.type) {
        case 'chat':
            renderMessage(data);
            break;
        case 'system':
            renderSystemMessage(data.text);
            break;
        case 'user_count':
            if (onlineCountEl) onlineCountEl.textContent = `${data.count} online`;
            break;
    }
}

// 10. RENDERIZARE MESAJE (Fix Aliniere Dreapta/Stânga)
function renderMessage(data) {
    // Verificare identitate: Comparăm numele expeditorului cu numele meu local
    // Folosim trim() pentru a evita erori de la spații goale accidentale
    const isMe = data.sender.trim() === myName.trim();
    const color = data.color || "blue";

    const row = document.createElement('div');
    // 'mine' merge la dreapta (CSS), 'theirs' la stânga (CSS)
    row.className = `message-row ${isMe ? 'mine' : 'theirs'}`;

    let content = "";
    if (!isMe) {
        // Numele apare doar deasupra mesajelor primite de la alții
        content += `<div class="sender-name">${data.sender}</div>`;
    }

    content += `<div class="bubble ${color}">${data.text}</div>`;

    row.innerHTML = content;
    msgList.appendChild(row);

    // Scroll automat la ultimul mesaj
    requestAnimationFrame(() => {
        msgList.scrollTop = msgList.scrollHeight;
    });
}

function renderSystemMessage(text) {
    const div = document.createElement('div');
    div.className = 'system-msg';
    div.innerText = text;
    msgList.appendChild(div);
    msgList.scrollTop = msgList.scrollHeight;
}

// 11. Evenimente Tastatură și UI Fixes
msgInput.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
});

// Fix pentru înălțimea ecranului pe iPhone (tastatura care ridică layout-ul)
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
if (isIOS) {
    function adjustChatHeight() {
        const chat = document.getElementById('chat-screen');
        if (chat) chat.style.height = window.innerHeight + 'px';
    }
    window.addEventListener('resize', adjustChatHeight);
    adjustChatHeight();
}

// 12. Pornire automată la încărcarea paginii
connectServer();

function toggleModal(show) {
    const modal = document.getElementById('info-modal');
    if (show) {
        modal.classList.remove('hidden');
    } else {
        modal.classList.add('hidden');
    }
}