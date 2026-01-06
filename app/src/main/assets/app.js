const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
const WS_URL = protocol + window.location.host;

let socket;
let myName = "";
let heartbeatInterval;
let isLoggedIn = false;
let pendingLogin = false;
let myBubbleColor = "blue";
let colorLocked = false;
const knownUsers = new Map();

document.addEventListener('DOMContentLoaded', () => {
    // 1. CLICK CULORI
    const colorOptions = document.querySelectorAll('.color-option');
    colorOptions.forEach(option => {
        option.addEventListener('click', () => {
            if (colorLocked) return;
            colorOptions.forEach(o => o.classList.remove('selected'));
            option.classList.add('selected');
            myBubbleColor = option.dataset.color;
        });
    });

    // 2. CLICK LOGIN
    const loginBtn = document.getElementById('login-btn');
    if (loginBtn) {
        loginBtn.addEventListener('click', login);
    }

    const loginInput = document.getElementById('username-input');
    if (loginInput) {
        loginInput.addEventListener("keydown", (e) => {
            if (e.key === "Enter") login();
        });
    }

    // 3. CHAT
    const sendBtn = document.getElementById('send-btn');
    if (sendBtn) sendBtn.addEventListener('click', sendMessage);

    const msgInput = document.getElementById('msg-input');
    if (msgInput) msgInput.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); }
    });

    // 4. MODAL LOGIC
    const onlineCountBtn = document.getElementById('online-count');
    const modal = document.getElementById('users-modal');
    const closeModalBtn = document.getElementById('close-modal-btn');

    if (onlineCountBtn && modal) {
        onlineCountBtn.addEventListener('click', () => {
            renderUserList();
            modal.classList.add('open');
        });
    }

    if (closeModalBtn && modal) {
        closeModalBtn.addEventListener('click', () => {
            modal.classList.remove('open');
        });
    }

    if (modal) {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) modal.classList.remove('open');
        });
    }

    adjustLayout();
    window.addEventListener('resize', adjustLayout);
    connectServer();
});

function adjustLayout() {
    const chat = document.getElementById('chat-screen');
    if (chat) chat.style.height = window.innerHeight + 'px';
}

function renderUserList() {
    const container = document.getElementById('users-list-container');
    container.innerHTML = "";
    addUserRow(container, myName + " (Eu)", myBubbleColor, true);
    knownUsers.forEach((color, name) => {
        if (name !== myName) addUserRow(container, name, color, false);
    });
    if (knownUsers.size === 0) {
        container.innerHTML += `<div style="padding:20px; text-align:center; color:#666; font-size:13px;">Nu există activitate recentă.</div>`;
    }
}

function addUserRow(container, name, color, isOnline) {
    const div = document.createElement('div');
    div.className = 'user-item';
    let bg = "#0084ff";
    if(color === "red") bg = "#ff3b30";
    if(color === "green") bg = "#34c759";
    if(color === "purple") bg = "#af52de";
    if(color === "orange") bg = "#ff9500";
    if(color === "white") bg = "#ffffff";
    const textColor = (color === "white") ? "black" : "white";

    div.innerHTML = `
        <div class="user-avatar" style="background:${bg}; color:${textColor}">
            ${name.charAt(0).toUpperCase()}
        </div>
        <div class="user-info">
            <span class="user-name-list">${name}</span>
            <span class="user-status-list">${isOnline ? 'Conectat' : 'Activ recent'}</span>
        </div>
    `;
    container.appendChild(div);
}

function login() {
    const input = document.getElementById('username-input');
    const name = input.value.trim();
    if (!name) { alert("Te rugăm să introduci un nume!"); return; }
    myName = name;
    if (socket && socket.readyState === WebSocket.OPEN) completeLogin();
    else {
        pendingLogin = true;
        renderSystemMessage("Se conectează la server...");
        if (!socket || socket.readyState === WebSocket.CLOSED) connectServer();
    }
}

function completeLogin() {
    if (isLoggedIn) return;
    isLoggedIn = true;
    pendingLogin = false;
    colorLocked = true;
    document.querySelector('.color-picker-container').style.display = 'none';
    document.getElementById('login-screen').classList.add('hidden');
    document.getElementById('chat-screen').classList.remove('hidden');
    document.getElementById('status-dot').classList.add('connected');
    sendPayload({ type: 'system', text: `${myName} s-a conectat.` });
    startHeartbeat();
}

function connectServer() {
    socket = new WebSocket(WS_URL);
    socket.onopen = () => {
        document.getElementById('status-dot').classList.add('connected');
        if (myName && (pendingLogin || !isLoggedIn)) completeLogin();
    };
    socket.onmessage = (event) => {
        if (event.data === "ping") return;
        try { handleData(JSON.parse(event.data)); } catch (e) { }
    };
    socket.onclose = () => {
        document.getElementById('status-dot').classList.remove('connected');
        renderSystemMessage("⚠️ Conexiune pierdută.");
        stopHeartbeat();
        isLoggedIn = false;
        setTimeout(connectServer, 3000);
    };
}

function startHeartbeat() {
    stopHeartbeat();
    heartbeatInterval = setInterval(() => {
        if (socket && socket.readyState === WebSocket.OPEN) socket.send("ping");
    }, 10000);
}

function stopHeartbeat() {
    if (heartbeatInterval) { clearInterval(heartbeatInterval); heartbeatInterval = null; }
}

function sendPayload(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        data.sender = myName;
        data.color = myBubbleColor;
        socket.send(JSON.stringify(data));
    }
}

function sendMessage() {
    const inp = document.getElementById('msg-input');
    const text = inp.value.trim();
    if (!text) return;
    sendPayload({ type: 'chat', text: text });
    inp.value = "";
    inp.focus();
}

function handleData(data) {
    if (data.sender && data.sender !== myName) knownUsers.set(data.sender, data.color || "blue");
    switch (data.type) {
        case 'chat': renderMessage(data); break;
        case 'system':
            if (data.text.includes("s-a conectat")) {
                const name = data.text.replace(" s-a conectat.", "");
                if(name) knownUsers.set(name, "blue");
            }
            renderSystemMessage(data.text);
            break;
        case 'user_count':
            const el = document.getElementById('online-count');
            if (el) el.textContent = `${data.count} online`;
            break;
    }
}

function renderMessage(data) {
    const list = document.getElementById('messages-list');
    const isMe = data.sender.trim() === myName.trim();
    const color = data.color || "blue";
    const row = document.createElement('div');
    row.className = `message-row ${isMe ? 'mine' : 'theirs'}`;
    let content = "";
    if (!isMe) content += `<div class="sender-name">${data.sender}</div>`;
    content += `<div class="bubble ${color}">${data.text}</div>`;
    row.innerHTML = content;
    list.appendChild(row);
    requestAnimationFrame(() => { list.scrollTop = list.scrollHeight; });
}

function renderSystemMessage(text) {
    const list = document.getElementById('messages-list');
    const div = document.createElement('div');
    div.className = 'system-msg';
    div.innerText = text;
    list.appendChild(div);
    list.scrollTop = list.scrollHeight;
}

// --- MODIFICARE AICI: Schimbare Text și Animație Buton ---
window.startPulsing = function() {
    console.log("Mesh Detected: Pulsing Button");
    const loginBtn = document.getElementById('login-btn');
    if (loginBtn) {
        // Schimbăm textul
        loginBtn.innerText = "Conectare în Mesh";
        // Adăugăm clasa de pulsare
        loginBtn.classList.add('pulsing-button-mode');
    }
};

window.stopPulsing = function() {
    console.log("Mesh Stopped: Normal Button");
    const loginBtn = document.getElementById('login-btn');
    if (loginBtn) {
        // Revenim la textul original
        loginBtn.innerText = "Conectare";
        // Scoatem clasa
        loginBtn.classList.remove('pulsing-button-mode');
    }
};