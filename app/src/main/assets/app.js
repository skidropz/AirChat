// URL WebSocket: același host + port ca pagina, pe path /ws
const WS_URL = "ws://" + window.location.host + "/ws";

// Variabile Globale
let socket;
let myName = "";
let heartbeatInterval; // pentru puls
let isLoggedIn = false;
let pendingLogin = false;

// Elemente DOM
const loginScreen = document.getElementById('login-screen');
const chatScreen = document.getElementById('chat-screen');
const msgList = document.getElementById('messages-list');
const msgInput = document.getElementById('msg-input');
const statusDot = document.getElementById('status-dot');
const onlineCountEl = document.getElementById('online-count');

// --- 1. LOGICA DE LOGIN ---
function login() {
    const input = document.getElementById('username-input');
    const name = input.value.trim();
    if (!name) {
        alert("Scrie un nume!");
        return;
    }

    myName = name;

    if (socket && socket.readyState === WebSocket.OPEN) {
        // conexiune deja gata -> intrăm instant în chat
        completeLogin();
    } else {
        // conexiunea nu e încă deschisă, așteptăm onopen
        pendingLogin = true;
        renderSystemMessage("Se conectează la server...");
    }
}

function completeLogin() {
    if (isLoggedIn) return;
    isLoggedIn = true;
    pendingLogin = false;

    loginScreen.classList.add('hidden');
    chatScreen.classList.remove('hidden');
    statusDot.classList.add('connected');

    sendPayload({ type: 'system', text: `${myName} s-a conectat.` });
    startHeartbeat();
}

// --- 2. LOGICA DE CONECTARE & HEARTBEAT ---
function connectServer() {
    socket = new WebSocket(WS_URL);

    socket.onopen = () => {
        statusDot.classList.add('connected');

        // dacă userul deja a apăsat login și așteaptă, finalizăm login-ul acum
        if (myName && (pendingLogin || !isLoggedIn)) {
            completeLogin();
        }
    };

    socket.onmessage = (event) => {
        // ignorăm ping-urile
        if (event.data === "ping") return;

        try {
            const data = JSON.parse(event.data);
            handleData(data);
        } catch (e) {
            console.log("Mesaj non-JSON primit:", event.data);
        }
    };

    socket.onclose = () => {
        statusDot.classList.remove('connected');
        renderSystemMessage("Deconectat de la server.");
        stopHeartbeat();
        isLoggedIn = false;
    };

    socket.onerror = (err) => {
        console.error("Eroare WebSocket:", err);
    };
}

function startHeartbeat() {
    if (heartbeatInterval) clearInterval(heartbeatInterval);
    heartbeatInterval = setInterval(() => {
        if (socket && socket.readyState === WebSocket.OPEN) {
            socket.send("ping");
        }
    }, 10000); // la 10s
}

function stopHeartbeat() {
    if (heartbeatInterval) {
        clearInterval(heartbeatInterval);
        heartbeatInterval = null;
    }
}

// Helper pentru trimiterea datelor JSON
function sendPayload(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        data.sender = myName; // cine trimite
        socket.send(JSON.stringify(data));
    } else {
        alert("Nu ești conectat la server!");
    }
}

// --- 3. LOGICA DE CHAT TEXT ---
function sendMessage() {
    const text = msgInput.value.trim();
    if (!text) return;

    sendPayload({ type: 'chat', text: text });
    msgInput.value = "";
    msgInput.focus();
}

// Router central pentru datele primite
async function handleData(data) {
    if (data.type === 'chat') {
        renderMessage(data);
    } else if (data.type === 'system') {
        renderSystemMessage(data.text);
    } else if (data.type === 'user_count') {
        updateUserCount(data.count);
    }
}

function updateUserCount(count) {
    if (!onlineCountEl) return;
    onlineCountEl.textContent = `${count} online`;
}

// Desenare mesaj
function renderMessage(data) {
    const isMe = data.sender === myName;

    const row = document.createElement('div');
    row.className = `message-row ${isMe ? 'mine' : 'theirs'}`;

    let content = "";
    if (!isMe) {
        content += `<div class="sender-name">${data.sender}</div>`;
    }

    content += `<div class="bubble">${data.text}</div>`;

    row.innerHTML = content;
    msgList.appendChild(row);

    msgList.scrollTop = msgList.scrollHeight;
}

function renderSystemMessage(text) {
    const div = document.createElement('div');
    div.className = 'system-msg';
    div.innerText = text;
    msgList.appendChild(div);
    msgList.scrollTop = msgList.scrollHeight;
}

// --- 4. ENTER = SEND + fix iPhone height ---
// ENTER = SEND (fără Shift)
msgInput.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
});

// Ajustare înălțime chat pentru iOS (tastatură care împinge layout-ul)
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);

if (isIOS) {
    function adjustChatHeight() {
        const chat = document.getElementById('chat-screen');
        if (!chat) return;
        chat.style.height = window.innerHeight + 'px';
    }

    window.addEventListener('resize', adjustChatHeight);
    window.addEventListener('orientationchange', adjustChatHeight);
    adjustChatHeight();
}

// --- 5. PORNIM CONEXIUNEA LA SERVER IMEDIAT CE PAGINA SE ÎNCARCĂ ---
connectServer();