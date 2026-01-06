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
let replyingTo = null;

const colorHexMap = { blue: '#0084ff', red: '#ff3b30', green: '#34c759', purple: '#af52de', orange: '#ff9500', white: '#ffffff' };
let unseenMsgQueue = new Set();

document.addEventListener('DOMContentLoaded', () => {
    // CULORI
    const colorOptions = document.querySelectorAll('.color-option');
    colorOptions.forEach(option => {
        option.addEventListener('click', () => {
            if (colorLocked) return;
            colorOptions.forEach(o => o.classList.remove('selected'));
            option.classList.add('selected');
            myBubbleColor = option.dataset.color;
            const loginBtn = document.getElementById('login-btn');
            if (loginBtn) {
                const hex = colorHexMap[myBubbleColor];
                loginBtn.style.backgroundColor = hex;
                loginBtn.style.borderColor = hex;
                loginBtn.style.color = (myBubbleColor === 'white') ? 'black' : 'white';
                document.documentElement.style.setProperty('--dynamic-btn-color', hex);
            }
        });
    });

    // VIZIBILITATE
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden && isLoggedIn) {
            if (unseenMsgQueue.size > 0) {
                unseenMsgQueue.forEach(msgId => sendSeen(msgId));
                unseenMsgQueue.clear();
            }
        }
    });

    // LISTENERS
    const loginBtn = document.getElementById('login-btn');
    if(loginBtn) loginBtn.addEventListener('click', login);
    const loginInput = document.getElementById('username-input');
    if(loginInput) loginInput.addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });
    const sendBtn = document.getElementById('send-btn');
    if(sendBtn) sendBtn.addEventListener('click', sendMessage);
    const msgInput = document.getElementById('msg-input');
    if(msgInput) msgInput.addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); } });

    // DECONECTARE
    const disconnectBtn = document.getElementById('disconnect-btn');
    if (disconnectBtn) disconnectBtn.addEventListener('click', () => window.location.reload());

    // PHOTO & BUZZ
    const photoBtn = document.getElementById('photo-btn');
    const fileInput = document.getElementById('file-input');
    if (photoBtn && fileInput) {
        photoBtn.addEventListener('click', () => fileInput.click());
        fileInput.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (file) { processAndSendImage(file); fileInput.value = ''; }
        });
    }

    // --- BUZZ ---
    const buzzBtn = document.getElementById('buzz-btn');
    if(buzzBtn) {
        buzzBtn.addEventListener('click', sendBuzz);
    }

    // MODAL & REPLY
    const closeImgBtn = document.getElementById('close-image-btn');
    const imgOverlay = document.getElementById('image-overlay');
    if(closeImgBtn && imgOverlay) {
        closeImgBtn.addEventListener('click', () => imgOverlay.classList.remove('active'));
        imgOverlay.addEventListener('click', (e) => { if(e.target === imgOverlay) imgOverlay.classList.remove('active'); });
    }
    const closeReplyBtn = document.getElementById('close-reply-btn');
    if (closeReplyBtn) closeReplyBtn.addEventListener('click', cancelReply);
    const onlineCountBtn = document.getElementById('online-count');
    const modal = document.getElementById('users-modal');
    const closeModalBtn = document.getElementById('close-modal-btn');
    if (onlineCountBtn && modal) onlineCountBtn.addEventListener('click', () => { renderUserList(); modal.classList.add('open'); });
    if (closeModalBtn && modal) closeModalBtn.addEventListener('click', () => modal.classList.remove('open'));
    if (modal) modal.addEventListener('click', (e) => { if (e.target === modal) modal.classList.remove('open'); });

    adjustLayout();
    window.addEventListener('resize', adjustLayout);
    connectServer();
});

// --- BUZZ LOGIC ---
function sendBuzz() {
    sendPayload({ type: 'buzz', sender: myName });
}

function handleBuzz(sender) {
    // 1. Vizual: Shake
    const body = document.getElementById('main-body');
    if(body) {
        body.classList.remove('shaking'); // Reset
        void body.offsetWidth; // Trigger reflow
        body.classList.add('shaking');
    }

    // 2. Mesaj sistem
    renderSystemMessage(`⚡ ${sender} a dat un BUZZ!`);

    // 3. Vibratie browser (pentru web)
    if (navigator.vibrate) {
        navigator.vibrate([200, 100, 200]);
    }
}

function generateId() { return 'msg-' + Date.now() + '-' + Math.floor(Math.random() * 1000); }
function openImage(src) { const overlay = document.getElementById('image-overlay'); const fullImg = document.getElementById('full-image'); if (overlay && fullImg) { fullImg.src = src; overlay.classList.add('active'); } }
function processAndSendImage(file) {
    const reader = new FileReader();
    reader.onload = function(event) {
        const img = new Image();
        img.onload = function() {
            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            const MAX_WIDTH = 800; const MAX_HEIGHT = 800;
            let width = img.width; let height = img.height;
            if (width > height) { if (width > MAX_WIDTH) { height *= MAX_WIDTH / width; width = MAX_WIDTH; } } else { if (height > MAX_HEIGHT) { width *= MAX_HEIGHT / height; height = MAX_HEIGHT; } }
            canvas.width = width; canvas.height = height; ctx.drawImage(img, 0, 0, width, height);
            const dataUrl = canvas.toDataURL('image/jpeg', 0.7);
            sendPayload({ type: 'image', id: generateId(), image: dataUrl });
        }
        img.src = event.target.result;
    }
    reader.readAsDataURL(file);
}
function adjustLayout() { const chat = document.getElementById('chat-screen'); if (chat) chat.style.height = window.innerHeight + 'px'; }
function renderUserList() {
    const container = document.getElementById('users-list-container');
    container.innerHTML = "";
    addUserRow(container, myName + " (Eu)", myBubbleColor, true);
    knownUsers.forEach((color, name) => { if (name !== myName) addUserRow(container, name, color, false); });
    if (knownUsers.size === 0) container.innerHTML += `<div style="padding:20px; text-align:center; color:#666; font-size:13px;">Nu există activitate recentă.</div>`;
}
function addUserRow(container, name, color, isOnline) {
    const div = document.createElement('div');
    div.className = 'user-item';
    let bg = colorHexMap[color] || "#555";
    const textColor = (color === "white") ? "black" : "white";
    div.innerHTML = `<div class="user-avatar" style="background:${bg}; color:${textColor}">${name.charAt(0).toUpperCase()}</div><div class="user-info"><span class="user-name-list">${name}</span><span class="user-status-list">${isOnline ? 'Conectat' : 'Activ recent'}</span></div>`;
    container.appendChild(div);
}
function login() {
    const input = document.getElementById('username-input');
    const name = input.value.trim();
    if (!name) { alert("Te rugăm să introduci un nume!"); return; }
    myName = name;
    if (socket && socket.readyState === WebSocket.OPEN) completeLogin();
    else { pendingLogin = true; renderSystemMessage("Se conectează la server..."); if (!socket || socket.readyState === WebSocket.CLOSED) connectServer(); }
}
function completeLogin() {
    if (isLoggedIn) return; isLoggedIn = true; pendingLogin = false; colorLocked = true;
    document.querySelector('.color-picker-container').style.display = 'none';
    document.getElementById('login-screen').classList.add('hidden');
    document.getElementById('chat-screen').classList.remove('hidden');
    document.getElementById('status-dot').classList.add('connected');
    sendPayload({ type: 'system', text: `${myName} s-a conectat.` });
    startHeartbeat(); updateOnlineCounter();
}
function connectServer() {
    socket = new WebSocket(WS_URL);
    socket.onopen = () => { document.getElementById('status-dot').classList.add('connected'); if (myName && (pendingLogin || !isLoggedIn)) completeLogin(); };
    socket.onmessage = (event) => { if (event.data === "ping") return; try { handleData(JSON.parse(event.data)); } catch (e) { } };
    socket.onclose = () => { document.getElementById('status-dot').classList.remove('connected'); renderSystemMessage("⚠️ Conexiune pierdută."); stopHeartbeat(); isLoggedIn = false; setTimeout(connectServer, 3000); };
}
function startHeartbeat() { stopHeartbeat(); heartbeatInterval = setInterval(() => { if (socket && socket.readyState === WebSocket.OPEN) socket.send("ping"); }, 10000); }
function stopHeartbeat() { if (heartbeatInterval) { clearInterval(heartbeatInterval); heartbeatInterval = null; } }
function sendPayload(data) { if (socket && socket.readyState === WebSocket.OPEN) { data.sender = myName; data.color = myBubbleColor; socket.send(JSON.stringify(data)); } }
function sendMessage() {
    const inp = document.getElementById('msg-input');
    const text = inp.value.trim(); if (!text) return;
    const msgId = generateId();
    const payload = { type: 'chat', id: msgId, text: text };
    if (replyingTo) { payload.replyTo = replyingTo; cancelReply(); }
    sendPayload(payload); inp.value = ""; inp.focus();
}
function handleData(data) {
    if (data.sender && data.sender !== myName) { if (!knownUsers.has(data.sender)) { knownUsers.set(data.sender, data.color || "blue"); updateOnlineCounter(); } else { knownUsers.set(data.sender, data.color || "blue"); } }
    switch (data.type) {
        case 'chat': renderMessage(data); break;
        case 'image': renderImageMessage(data); break;
        case 'buzz': handleBuzz(data.sender); break; // NOU
        case 'system': if (data.text.includes("s-a conectat")) { const name = data.text.replace(" s-a conectat.", ""); if(name && name !== myName) { knownUsers.set(name, "blue"); updateOnlineCounter(); } } renderSystemMessage(data.text); break;
        case 'seen': handleSeenEvent(data); break;
    }
}
function sendSeen(msgId) { if(!msgId) return; sendPayload({ type: 'seen', seenMsgId: msgId, seenBy: myName }); }
function handleSeenEvent(data) {
    const msgId = data.seenMsgId; const who = data.seenBy; if(!msgId || !who || who === myName) return;
    const msgRow = document.getElementById(msgId);
    if(msgRow) {
        let seenLabel = msgRow.querySelector('.seen-label');
        if(!seenLabel) { seenLabel = document.createElement('div'); seenLabel.className = 'seen-label'; msgRow.appendChild(seenLabel); }
        const currentText = seenLabel.textContent; if(currentText.includes(who)) return;
        seenLabel.textContent = (currentText === "") ? `Văzut de ${who}` : `${currentText}, ${who}`;
    }
}
function updateOnlineCounter() { const el = document.getElementById('online-count'); const count = 1 + knownUsers.size; if (el) el.textContent = `${count} online`; }
function attachSwipeListeners(element, messageData) {
    let startX = 0; let currentX = 0;
    element.addEventListener('touchstart', (e) => { startX = e.touches[0].clientX; }, {passive: true});
    element.addEventListener('touchmove', (e) => { currentX = e.touches[0].clientX; const diff = currentX - startX; if (diff > 0 && diff < 100) element.style.transform = `translateX(${diff}px)`; }, {passive: true});
    element.addEventListener('touchend', () => { const diff = currentX - startX; element.style.transform = 'translateX(0)'; if (diff > 50) triggerReply(messageData); startX = 0; currentX = 0; });
    element.addEventListener('dblclick', () => { triggerReply(messageData); });
}
function triggerReply(messageData) { const replyText = messageData.type === 'image' ? '[Imagine]' : messageData.text; replyingTo = { id: messageData.id, sender: messageData.sender, text: replyText }; document.getElementById('reply-bar').classList.remove('hidden'); document.getElementById('reply-target-name').textContent = messageData.sender; document.getElementById('reply-target-text').textContent = replyText; document.getElementById('msg-input').focus(); }
function cancelReply() { replyingTo = null; document.getElementById('reply-bar').classList.add('hidden'); }
function scrollToMessage(msgId) { const el = document.getElementById(msgId); if(el) { el.scrollIntoView({ behavior: 'smooth', block: 'center' }); el.classList.add('highlight-message'); setTimeout(() => el.classList.remove('highlight-message'), 1500); } }
function renderMessage(data) {
    if (!data.id) data.id = generateId();
    const list = document.getElementById('messages-list'); const isMe = data.sender.trim() === myName.trim(); const color = data.color || "blue";
    const row = document.createElement('div'); row.className = `message-row ${isMe ? 'mine' : 'theirs'}`; row.id = data.id; attachSwipeListeners(row, data);
    let content = ""; if (!isMe) content += `<div class="sender-name">${data.sender}</div>`;
    content += `<div class="bubble ${color}">`;
    if (data.replyTo) { const origId = data.replyTo.id; content += `<div class="reply-preview-in-message" onclick="scrollToMessage('${origId}')"><span class="reply-from-name">${data.replyTo.sender}</span><span class="reply-original-text">${data.replyTo.text}</span></div>`; }
    content += `${data.text}</div>`; row.innerHTML = content; list.appendChild(row); requestAnimationFrame(() => { list.scrollTop = list.scrollHeight; });
    if (!isMe) { if (document.hidden) { unseenMsgQueue.add(data.id); } else { sendSeen(data.id); } }
}
function renderImageMessage(data) {
    if (!data.id) data.id = generateId();
    const list = document.getElementById('messages-list'); const isMe = data.sender.trim() === myName.trim(); const color = data.color || "blue";
    const row = document.createElement('div'); row.className = `message-row ${isMe ? 'mine' : 'theirs'}`; row.id = data.id; attachSwipeListeners(row, data);
    let content = ""; if (!isMe) content += `<div class="sender-name">${data.sender}</div>`;
    content += `<div class="bubble ${color} has-image">`;
    if (data.replyTo) { const origId = data.replyTo.id; content += `<div class="reply-preview-in-message" onclick="scrollToMessage('${origId}')"><span class="reply-from-name">${data.replyTo.sender}</span><span class="reply-original-text">${data.replyTo.text}</span></div>`; }
    content += `<img src="${data.image}" class="chat-image" alt="Imagine" onclick="openImage('${data.image}')">`; content += `</div>`; row.innerHTML = content; list.appendChild(row); requestAnimationFrame(() => { list.scrollTop = list.scrollHeight; });
    if (!isMe) { if (document.hidden) { unseenMsgQueue.add(data.id); } else { sendSeen(data.id); } }
}
function renderSystemMessage(text) { const list = document.getElementById('messages-list'); const div = document.createElement('div'); div.className = 'system-msg'; div.innerText = text; list.appendChild(div); list.scrollTop = list.scrollHeight; }
window.startPulsing = function() { const btn = document.getElementById('login-btn'); if(btn) { btn.innerText="Conectare în Mesh"; btn.classList.add('pulsing-button-mode'); } };
window.stopPulsing = function() { const btn = document.getElementById('login-btn'); if(btn) { btn.innerText="CONECTARE"; btn.classList.remove('pulsing-button-mode'); } };