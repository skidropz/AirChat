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

// --- AUDIO VARIABLES ---
let mediaRecorder = null;
let audioChunks = [];
let isRecording = false;
let recordingStartTime = 0;
let recordingTimerInterval = null;
let isRecordingCancelled = false;

// --- SPARKLER VARIABLES ---
let sparklerInterval = null;
let currentTouchX = 0;
let currentTouchY = 0;

// --- COMPASS VARIABLES ---
let myLat = 0;
let myLon = 0;
let myHeading = 0;
let targetUserForCompass = null;
const userLocations = new Map();

document.addEventListener('DOMContentLoaded', () => {
    // 1. CULORI
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

    // 2. VIZIBILITATE
    document.addEventListener('visibilitychange', () => {
        if (!document.hidden && isLoggedIn) {
            if (unseenMsgQueue.size > 0) {
                unseenMsgQueue.forEach(msgId => sendSeen(msgId));
                unseenMsgQueue.clear();
            }
        }
    });

    // 3. UI LISTENERS
    const loginBtn = document.getElementById('login-btn');
    if(loginBtn) loginBtn.addEventListener('click', login);
    const loginInput = document.getElementById('username-input');
    if(loginInput) loginInput.addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });

    const sendBtn = document.getElementById('send-btn');
    const micBtn = document.getElementById('mic-btn');
    const msgInput = document.getElementById('msg-input');

    if (msgInput) {
        msgInput.addEventListener('input', () => {
            if (msgInput.value.trim().length > 0) {
                sendBtn.classList.remove('hidden');
                micBtn.classList.add('hidden');
            } else {
                sendBtn.classList.add('hidden');
                micBtn.classList.remove('hidden');
            }
        });
        msgInput.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); }
        });
    }

    if(sendBtn) sendBtn.addEventListener('click', sendMessage);

    // 4. MIC BUTTON (SPARKLERS & RECORDING)
    if (micBtn) {
        micBtn.addEventListener('mousedown', startRecording);
        micBtn.addEventListener('mouseup', stopRecording);
        micBtn.addEventListener('mouseleave', () => { if(isRecording) cancelRecording(); });

        micBtn.addEventListener('touchstart', (e) => {
            e.preventDefault();
            startRecording();
            startSparkler(e.touches[0].clientX, e.touches[0].clientY);
        });

        micBtn.addEventListener('touchmove', (e) => {
            if (!isRecording || isRecordingCancelled) return;
            const touch = e.touches[0];
            currentTouchX = touch.clientX;
            currentTouchY = touch.clientY;

            const btnRect = micBtn.getBoundingClientRect();
            const diffX = touch.clientX - (btnRect.left + btnRect.width/2);

            if (diffX < 0 && diffX > -150) {
                micBtn.style.transform = `translateX(${diffX}px) scale(1.2)`;
            }

            if (diffX < -100) {
                crashAndCancel(touch.clientX, touch.clientY);
            }
        });

        micBtn.addEventListener('touchend', (e) => {
            e.preventDefault();
            micBtn.style.transform = '';
            stopSparkler();
            if (!isRecordingCancelled) stopRecording();
        });
    }

    const disconnectBtn = document.getElementById('disconnect-btn');
    if (disconnectBtn) disconnectBtn.addEventListener('click', () => window.location.reload());

    const photoBtn = document.getElementById('photo-btn');
    const fileInput = document.getElementById('file-input');
    if (photoBtn && fileInput) {
        photoBtn.addEventListener('click', () => fileInput.click());
        fileInput.addEventListener('change', (e) => {
            const file = e.target.files[0];
            if (file) { processAndSendImage(file); fileInput.value = ''; }
        });
    }

    const buzzBtn = document.getElementById('buzz-btn');
    if(buzzBtn) buzzBtn.addEventListener('click', sendBuzz);

    // 5. MODALE
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

    // 6. BUSOLA MODAL
    const compassModal = document.getElementById('compass-overlay');
    const closeCompassBtn = document.getElementById('close-compass-btn');
    if (closeCompassBtn && compassModal) {
        closeCompassBtn.addEventListener('click', () => {
            compassModal.classList.remove('open');
            targetUserForCompass = null;
        });
    }

    adjustLayout();
    window.addEventListener('resize', adjustLayout);
    connectServer();

    // 7. START BUSOLA LOOP
    setInterval(updateCompassUI, 200);
});

// ========================
// === COMPASS LOGIC    ===
// ========================
window.updateMyLocation = function(lat, lon) { myLat = lat; myLon = lon; }
window.updateMyHeading = function(azimuth) { myHeading = azimuth; }

function openCompass(targetName) {
    if (!userLocations.has(targetName)) { alert("Acest utilizator nu are GPS-ul activat."); return; }
    targetUserForCompass = targetName;
    document.getElementById('compass-target-name').innerText = targetName;
    document.getElementById('users-modal').classList.remove('open');
    document.getElementById('compass-overlay').classList.add('open');
}

function updateCompassUI() {
    if (!targetUserForCompass) return;

    const distEl = document.getElementById('compass-distance');
    const labelEl = document.querySelector('.compass-info small');
    const targetLoc = userLocations.get(targetUserForCompass);

    if (!targetLoc || myLat === 0 || myLon === 0) {
        distEl.innerText = "Caut semnal...";
        distEl.classList.add('waiting');
        if(labelEl) labelEl.classList.add('hidden-label');
        return;
    }

    distEl.classList.remove('waiting');
    if(labelEl) labelEl.classList.remove('hidden-label');

    const dist = calculateDistance(myLat, myLon, targetLoc.lat, targetLoc.lon);
    let distText = (dist < 1000) ? Math.round(dist) + " m" : (dist / 1000).toFixed(2) + " km";
    distEl.innerText = distText;

    const targetBearing = calculateBearing(myLat, myLon, targetLoc.lat, targetLoc.lon);
    let rotation = targetBearing - myHeading;
    const arrow = document.getElementById('compass-arrow');
    if (arrow) { arrow.style.transform = `rotate(${rotation}deg)`; }
}

function calculateDistance(lat1, lon1, lat2, lon2) {
    const R = 6371e3; const φ1 = lat1 * Math.PI/180; const φ2 = lat2 * Math.PI/180;
    const Δφ = (lat2-lat1) * Math.PI/180; const Δλ = (lon2-lon1) * Math.PI/180;
    const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) + Math.cos(φ1) * Math.cos(φ2) * Math.sin(Δλ/2) * Math.sin(Δλ/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
}

function calculateBearing(startLat, startLng, destLat, destLng) {
    startLat = toRadians(startLat); startLng = toRadians(startLng); destLat = toRadians(destLat); destLng = toRadians(destLng);
    const y = Math.sin(destLng - startLng) * Math.cos(destLat);
    const x = Math.cos(startLat) * Math.sin(destLat) - Math.sin(startLat) * Math.cos(destLat) * Math.cos(destLng - startLng);
    let brng = Math.atan2(y, x); brng = toDegrees(brng); return (brng + 360) % 360;
}
function toRadians(deg) { return deg * (Math.PI/180); }
function toDegrees(rad) { return rad * (180/Math.PI); }

// ========================
// === SPARKLER LOGIC   ===
// ========================
function startSparkler(x, y) {
    currentTouchX = x; currentTouchY = y;
    if (sparklerInterval) clearInterval(sparklerInterval);
    sparklerInterval = setInterval(() => {
        createSwipeParticle(currentTouchX, currentTouchY);
        createSwipeParticle(currentTouchX, currentTouchY);
    }, 40);
}

function stopSparkler() {
    if (sparklerInterval) { clearInterval(sparklerInterval); sparklerInterval = null; }
}

function createSwipeParticle(x, y) {
    const p = document.createElement('div'); p.className = 'swipe-particle';
    const offsetX = (Math.random() - 0.5) * 20; const offsetY = (Math.random() - 0.5) * 20;
    p.style.left = (x + offsetX) + 'px'; p.style.top = (y + offsetY) + 'px';
    const colors = ['#FFD700', '#FFA500', '#FFFFFF', '#FFFFE0'];
    p.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
    const angle = Math.random() * 2 * Math.PI; const velocity = 30 + Math.random() * 50;
    const tx = Math.cos(angle) * velocity; const ty = Math.sin(angle) * velocity;
    p.style.setProperty('--tx', `${tx}px`); p.style.setProperty('--ty', `${ty}px`);
    document.body.appendChild(p); setTimeout(() => p.remove(), 600);
}

function crashAndCancel(x, y) {
    if (isRecordingCancelled) return;
    stopSparkler();

    // EXPLOSION
    for(let i=0; i<60; i++) {
        const p = document.createElement('div'); p.className = 'explosion-particle';
        p.style.left = x + 'px'; p.style.top = y + 'px';
        const colors = ['#FF4500', '#FF8C00', '#FFD700', '#FFFFFF'];
        p.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)];
        const angle = Math.random() * 2 * Math.PI; const velocity = 50 + Math.random() * 200;
        const ex = Math.cos(angle) * velocity; const ey = Math.sin(angle) * velocity;
        p.style.setProperty('--ex', `${ex}px`); p.style.setProperty('--ey', `${ey}px`);
        document.body.appendChild(p); setTimeout(() => p.remove(), 800);
    }

    const body = document.getElementById('main-body');
    body.classList.remove('shaking'); void body.offsetWidth; body.classList.add('shaking');
    if (navigator.vibrate) navigator.vibrate(100);
    cancelRecording();
    const micBtn = document.getElementById('mic-btn'); if(micBtn) micBtn.style.transform = '';
}

// ========================
// === AUDIO RECORDING  ===
// ========================
async function startRecording() {
    if (isRecording) return;
    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        mediaRecorder = new MediaRecorder(stream);
        audioChunks = []; isRecordingCancelled = false;
        mediaRecorder.ondataavailable = event => { audioChunks.push(event.data); };
        mediaRecorder.onstop = () => {
            stream.getTracks().forEach(track => track.stop());
            if (isRecordingCancelled) return;
            const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
            const reader = new FileReader(); reader.readAsDataURL(audioBlob);
            reader.onloadend = () => {
                const base64Audio = reader.result;
                sendPayload({ type: 'audio', id: generateId(), audio: base64Audio });
            };
        };
        mediaRecorder.start(); isRecording = true;
        document.getElementById('recording-overlay').classList.remove('hidden');
        document.getElementById('mic-btn').classList.add('active');
        recordingStartTime = Date.now(); updateTimer();
        recordingTimerInterval = setInterval(updateTimer, 1000);
    } catch (err) { alert("Nu pot accesa microfonul!"); }
}

function stopRecording() { if (!isRecording) return; if (mediaRecorder && mediaRecorder.state !== 'inactive') { mediaRecorder.stop(); } resetRecordingUI(); }
function cancelRecording() { if (!isRecording) return; isRecordingCancelled = true; if (mediaRecorder && mediaRecorder.state !== 'inactive') { mediaRecorder.stop(); } resetRecordingUI(); }
function resetRecordingUI() { isRecording = false; clearInterval(recordingTimerInterval); document.getElementById('recording-overlay').classList.add('hidden'); document.getElementById('mic-btn').classList.remove('active'); document.getElementById('mic-btn').style.transform = ''; document.getElementById('rec-timer').innerText = "00:00"; }
function updateTimer() { const diff = Math.floor((Date.now() - recordingStartTime) / 1000); const m = Math.floor(diff / 60).toString().padStart(2, '0'); const s = (diff % 60).toString().padStart(2, '0'); document.getElementById('rec-timer').innerText = `${m}:${s}`; }

// ========================
// === CORE FUNCTIONS   ===
// ========================
function sendBuzz() { sendPayload({ type: 'buzz', sender: myName }); }
function handleBuzz(sender) {
    const body = document.getElementById('main-body');
    if(body) { body.classList.remove('shaking'); void body.offsetWidth; body.classList.add('shaking'); }
    renderSystemMessage(`⚡ ${sender} a dat un BUZZ!`);
    if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
}
function generateId() { return 'msg-' + Date.now() + '-' + Math.floor(Math.random() * 1000); }
function openImage(src) { const overlay = document.getElementById('image-overlay'); const fullImg = document.getElementById('full-image'); if (overlay && fullImg) { fullImg.src = src; overlay.classList.add('active'); } }
function processAndSendImage(file) {
    const reader = new FileReader(); reader.onload = function(event) {
        const img = new Image(); img.onload = function() {
            const canvas = document.createElement('canvas'); const ctx = canvas.getContext('2d');
            const MAX_WIDTH = 800; const MAX_HEIGHT = 800; let width = img.width; let height = img.height;
            if (width > height) { if (width > MAX_WIDTH) { height *= MAX_WIDTH / width; width = MAX_WIDTH; } } else { if (height > MAX_HEIGHT) { width *= MAX_HEIGHT / height; height = MAX_HEIGHT; } }
            canvas.width = width; canvas.height = height; ctx.drawImage(img, 0, 0, width, height);
            const dataUrl = canvas.toDataURL('image/jpeg', 0.7); sendPayload({ type: 'image', id: generateId(), image: dataUrl });
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

    // --- AICI ERA PROBLEMA (CLICK BUSOLA) ---
    div.onclick = function() {
        if (name !== myName) openCompass(name);
    };

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
    const input = document.getElementById('username-input'); const name = input.value.trim();
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

    // PORNIM LOCATION BROADCAST
    setInterval(() => {
        if (isLoggedIn && socket && socket.readyState === WebSocket.OPEN && myLat !== 0) {
            socket.send(JSON.stringify({ type: 'location_update', sender: myName, lat: myLat, lon: myLon }));
        }
    }, 3000);
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
    document.getElementById('send-btn').classList.add('hidden');
    document.getElementById('mic-btn').classList.remove('hidden');
}
function handleData(data) {
    if (data.type === 'location_update') {
        if (data.sender && data.sender !== myName) {
            userLocations.set(data.sender, { lat: data.lat, lon: data.lon });
            if (targetUserForCompass === data.sender) updateCompassUI();
        }
        return;
    }
    if (data.sender && data.sender !== myName) { if (!knownUsers.has(data.sender)) { knownUsers.set(data.sender, data.color || "blue"); updateOnlineCounter(); } else { knownUsers.set(data.sender, data.color || "blue"); } }
    switch (data.type) {
        case 'chat': renderMessage(data); break;
        case 'image': renderImageMessage(data); break;
        case 'audio': renderAudioMessage(data); break;
        case 'buzz': handleBuzz(data.sender); break;
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
function triggerReply(messageData) {
    let replyText = messageData.text;
    if (messageData.type === 'image') replyText = '[Imagine]';
    if (messageData.type === 'audio') replyText = '[Mesaj Vocal 🎤]';
    replyingTo = { id: messageData.id, sender: messageData.sender, text: replyText };
    document.getElementById('reply-bar').classList.remove('hidden'); document.getElementById('reply-target-name').textContent = messageData.sender; document.getElementById('reply-target-text').textContent = replyText; document.getElementById('msg-input').focus();
}
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
function renderAudioMessage(data) {
    if (!data.id) data.id = generateId();
    const list = document.getElementById('messages-list'); const isMe = data.sender.trim() === myName.trim(); const color = data.color || "blue";
    const row = document.createElement('div'); row.className = `message-row ${isMe ? 'mine' : 'theirs'}`; row.id = data.id; attachSwipeListeners(row, data);
    let content = ""; if (!isMe) content += `<div class="sender-name">${data.sender}</div>`;
    const playerID = 'audio-' + data.id; const waveID = 'wave-' + playerID;
    content += `<div class="bubble ${color}">`;
    if (data.replyTo) { const origId = data.replyTo.id; content += `<div class="reply-preview-in-message" onclick="scrollToMessage('${origId}')"><span class="reply-from-name">${data.replyTo.sender}</span><span class="reply-original-text">${data.replyTo.text}</span></div>`; }
    content += `<div class="custom-audio-player"><button class="audio-play-btn" onclick="toggleAudio('${playerID}')"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg></button><div class="audio-waveform" id="${waveID}"></div><audio id="${playerID}" src="${data.audio}" style="display:none;" ontimeupdate="updateWaveform('${playerID}')" onended="resetAudio('${playerID}')"></audio></div>`;
    content += `</div>`; row.innerHTML = content; list.appendChild(row); requestAnimationFrame(() => { list.scrollTop = list.scrollHeight; });
    generateRealWaveform(data.audio, waveID);
    if (!isMe) { if (document.hidden) { unseenMsgQueue.add(data.id); } else { sendSeen(data.id); } }
}
async function generateRealWaveform(base64, containerID) {
    try {
        const response = await fetch(base64); const arrayBuffer = await response.arrayBuffer(); const audioContext = new (window.AudioContext || window.webkitAudioContext)(); const audioBuffer = await audioContext.decodeAudioData(arrayBuffer); const rawData = audioBuffer.getChannelData(0);
        const samples = 30; const blockSize = Math.floor(rawData.length / samples); const container = document.getElementById(containerID); if(!container) return; container.innerHTML = "";
        for (let i = 0; i < samples; i++) { let sum = 0; for (let j = 0; j < blockSize; j++) { sum += Math.abs(rawData[i * blockSize + j]); } let avg = sum / blockSize; let height = Math.max(4, Math.min(25, avg * 150)); const bar = document.createElement('div'); bar.className = 'waveform-bar'; bar.style.height = `${height}px`; container.appendChild(bar); }
    } catch(e) { const container = document.getElementById(containerID); if(container) { container.innerHTML = ""; for(let i=0; i<30; i++) { const h = 5 + Math.floor(Math.random()*15); container.innerHTML += `<div class="waveform-bar" style="height:${h}px"></div>`; } } }
}
window.toggleAudio = function(id) { const audio = document.getElementById(id); if (!audio) return; document.querySelectorAll('audio').forEach(a => { if(a.id !== id) { a.pause(); resetAudio(a.id); } }); const btn = audio.parentElement.querySelector('.audio-play-btn'); if (audio.paused) { audio.play(); btn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>`; } else { audio.pause(); btn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`; } };
window.updateWaveform = function(id) { const audio = document.getElementById(id); const container = document.getElementById('wave-' + id); if (!audio || !container) return; const percent = (audio.currentTime / audio.duration) * 100; const bars = container.querySelectorAll('.waveform-bar'); const activeCount = Math.floor((percent / 100) * bars.length); bars.forEach((bar, index) => { if (index < activeCount) bar.classList.add('active'); else bar.classList.remove('active'); }); };
window.resetAudio = function(id) { const audio = document.getElementById(id); const container = document.getElementById('wave-' + id); if (audio) { const btn = audio.parentElement.querySelector('.audio-play-btn'); btn.innerHTML = `<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>`; } if (container) { container.querySelectorAll('.waveform-bar').forEach(b => b.classList.remove('active')); } };
function renderSystemMessage(text) { const list = document.getElementById('messages-list'); const div = document.createElement('div'); div.className = 'system-msg'; div.innerText = text; list.appendChild(div); list.scrollTop = list.scrollHeight; }
window.startPulsing = function() { const btn = document.getElementById('login-btn'); if(btn) { btn.innerText="Conectare în Mesh"; btn.classList.add('pulsing-button-mode'); } };
window.stopPulsing = function() { const btn = document.getElementById('login-btn'); if(btn) { btn.innerText="Conectare"; btn.classList.remove('pulsing-button-mode'); } };