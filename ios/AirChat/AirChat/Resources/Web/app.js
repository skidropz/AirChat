const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
const WS_URL = protocol + window.location.host;

let socket;
let reconnectTimeout = null;
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
let activeChat = 'general';
let unreadCounts = {};
let lastMessageSenders = {};
let lastMessageRows = {};

window.openPrivateChat = function(name) {
    if (name === myName || name === myName + t("you_suffix")) return;
    document.getElementById('users-modal').classList.remove('open');
    activeChat = name;
    document.getElementById('general-header-title').classList.add('hidden');
    document.getElementById('private-header-title').classList.remove('hidden');
    document.getElementById('private-target-name').innerText = name;
    unreadCounts[name] = 0;
    updateUnreadBadges();
    filterChatMessages();
};

window.backToGeneralChat = function() {
    activeChat = 'general';
    document.getElementById('general-header-title').classList.remove('hidden');
    document.getElementById('private-header-title').classList.add('hidden');
    filterChatMessages();
};

function filterChatMessages() {
    document.querySelectorAll('.message-row, .system-msg').forEach(row => {
        if (row.dataset.chatGroup === activeChat) {
            row.classList.remove('hidden-chat');
        } else {
            row.classList.add('hidden-chat');
        }
    });
    const list = document.getElementById('messages-list');
    list.scrollTop = list.scrollHeight;
}

function updateUnreadBadges() {
    let total = 0;
    for (let k in unreadCounts) total += unreadCounts[k];
    const badge = document.getElementById('global-unread-badge');
    if (badge) {
        if (total > 0) {
            badge.innerText = total;
            badge.classList.remove('hidden');
        } else {
            badge.classList.add('hidden');
        }
    }
    const modal = document.getElementById('users-modal');
    if (modal && modal.classList.contains('open')) {
        renderUserList();
    }
}

// --- AUDIO VARIABLES ---
let mediaRecorder = null;
let audioChunks = [];
let isRecording = false;
let isRecordingRequested = false;
let recordingStartTime = 0;
let recordingTimerInterval = null;
let isRecordingCancelled = false;

// --- SPARKLER VARIABLES ---
let sparklerInterval = null;
let currentTouchX = 0;
let currentTouchY = 0;

// --- COMPASS & STATUS VARIABLES ---
let myLat = 0;
let myLon = 0;
let myHeading = 0;
let myBattery = null;
let targetUserForCompass = null;
const userLocations = new Map();
let locationInterval = null;

// --- CRYPTO VARIABLES ---
let roomCryptoKey = null;

async function initCrypto() {
    let hash = window.location.hash.substring(1);
    if (!hash) {
        hash = prompt("Introdu codul camerei (dacă nu ai scanat un cod QR):");
        if (hash) {
            window.location.hash = hash;
        } else {
            alert("Aplicația are nevoie de codul camerei pentru a decripta mesajele!");
            return;
        }
    }
    try {
        roomCryptoKey = decodeURIComponent(hash).trim();
    } catch (e) {
        console.error("Eroare la inițializarea cheii:", e);
        alert("Cod de cameră invalid!");
    }
}

function xorCipher(text, key) {
    let result = '';
    for (let i = 0; i < text.length; i++) {
        result += String.fromCharCode(text.charCodeAt(i) ^ key.charCodeAt(i % key.length));
    }
    return result;
}

async function encryptData(dataStr) {
    if (!roomCryptoKey) return dataStr;
    try {
        const encoded = encodeURIComponent(dataStr);
        const xored = xorCipher(encoded, roomCryptoKey);
        return btoa(xored);
    } catch(e) {
        return dataStr;
    }
}

async function decryptData(encryptedStr) {
    if (!roomCryptoKey) return encryptedStr;
    try {
        const xored = atob(encryptedStr);
        const decoded = xorCipher(xored, roomCryptoKey);
        return decodeURIComponent(decoded);
    } catch (e) {
        console.warn("Eroare decriptare", e);
        return "[Mesaj criptat care nu a putut fi decriptat]";
    }
}

// --- TRANSLATIONS ---
const translations = {
    ro: {
        name_placeholder: "Numele tău",
        connect_btn: "Conectare",
        choose_color: "Alege culoarea pentru mesajele tale",
        disconnect_btn: "Deconectare",
        reply_to: "Răspuns pentru",
        swipe_cancel: "Glisează la stânga pentru anulare ⬅",
        type_msg: "Scrie un mesaj...",
        active_users: "Utilizatori activi",
        locate_hint: "Apasă pe un utilizator pentru localizare.",
        looking_for: "Îl căutăm pe",
        calculating: "Calculare...",
        distance: "DISTANȚĂ",
        alert_name: "Te rugăm să introduci un nume!",
        alert_mic: "Nu pot accesa microfonul!",
        sys_connecting: "Se conectează la server...",
        sys_connected: " s-a conectat.",
        sys_lost: "⚠️ Conexiune pierdută.",
        reply_img: "[Imagine]",
        reply_audio: "[Mesaj Vocal 🎤]",
        seen_by: "Văzut de ",
        status_online: "Conectat",
        status_recent: "Activ recent",
        no_activity: "Nu există activitate recentă.",
        buzz_msg: "⚡ {sender} a dat un BUZZ!",
        you_suffix: " (Eu)",
        searching_signal: "Caut semnal...",
        km_suffix: " km",
        m_suffix: " m",
        online_count: "{count} online",
        download_apk: "Ești pe Android? Descarcă aplicația nativă aici!"
    },
    en: {
        name_placeholder: "Your name",
        connect_btn: "Connect",
        choose_color: "Choose your message color",
        disconnect_btn: "Disconnect",
        reply_to: "Replying to",
        swipe_cancel: "Swipe left to cancel ⬅",
        type_msg: "Type a message...",
        active_users: "Active users",
        locate_hint: "Tap a user to locate them.",
        looking_for: "Looking for",
        calculating: "Calculating...",
        distance: "DISTANCE",
        alert_name: "Please enter a name!",
        alert_mic: "Cannot access microphone!",
        sys_connecting: "Connecting to server...",
        sys_connected: " joined.",
        sys_lost: "⚠️ Connection lost.",
        reply_img: "[Image]",
        reply_audio: "[Voice Message 🎤]",
        seen_by: "Seen by ",
        status_online: "Online",
        status_recent: "Recently active",
        no_activity: "No recent activity.",
        buzz_msg: "⚡ {sender} sent a BUZZ!",
        you_suffix: " (Me)",
        searching_signal: "Searching signal...",
        km_suffix: " km",
        m_suffix: " m",
        online_count: "{count} online",
        download_apk: "Are you on Android? Download the native app here!"
    }
};

let currentLang = localStorage.getItem('lang') || 'ro';

function t(key, params = {}) {
    let str = translations[currentLang][key] || key;
    for (const [k, v] of Object.entries(params)) {
        str = str.replace(`{${k}}`, v);
    }
    return str;
}

function applyTranslations() {
    document.querySelectorAll('[data-i18n]').forEach(el => {
        el.innerText = t(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
        el.placeholder = t(el.getAttribute('data-i18n-placeholder'));
    });
    document.querySelectorAll('.lang-option').forEach(el => {
        if (el.getAttribute('data-lang') === currentLang) el.classList.add('active');
        else el.classList.remove('active');
    });
    updateOnlineCounter(); // Refresh online text
}

// Pornim Geo-locația în browser pentru clienții web
if (navigator.geolocation) {
    navigator.geolocation.watchPosition((pos) => {
        myLat = pos.coords.latitude;
        myLon = pos.coords.longitude;
    }, (err) => {
        console.warn('Eroare la obținerea locației din browser:', err);
    }, { enableHighAccuracy: true });
}

// Citim bateria (daca este suportata de browser)
if (navigator.getBattery) {
    navigator.getBattery().then(batt => {
        myBattery = Math.round(batt.level * 100);
        batt.addEventListener('levelchange', () => {
            myBattery = Math.round(batt.level * 100);
        });
    }).catch(e => console.warn("Battery API:", e));
}

// Fallback nativ pentru aplicatia Android
setInterval(() => {
    try {
        if (window.AndroidInterface && typeof window.AndroidInterface.getBatteryLevel === 'function') {
            const b = window.AndroidInterface.getBatteryLevel();
            if (b > 0) myBattery = b;
        }
    } catch(e) {}
}, 10000);

// Ascultăm evenimentele de orientare pentru busola din browser
if (window.DeviceOrientationEvent) {
    window.addEventListener('deviceorientation', function(event) {
        if (event.webkitCompassHeading) {
            myHeading = event.webkitCompassHeading;
        } else if (event.alpha !== null) {
            myHeading = 360 - event.alpha;
        }
    });
}

document.addEventListener('DOMContentLoaded', () => {
    // -1. INIT TRANSLATIONS
    applyTranslations();

    document.querySelectorAll('.lang-option').forEach(btn => {
        btn.addEventListener('click', (e) => {
            currentLang = e.target.getAttribute('data-lang');
            localStorage.setItem('lang', currentLang);
            applyTranslations();
            if (isLoggedIn) renderUserList(); // refresh names
        });
    });

    // 0. INIT CRYPTO & PWA Service Worker
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('sw.js').catch(err => console.log('SW Reg Failed', err));
    }
    initCrypto();

    // 0. THEME SETUP
    const themeToggle = document.getElementById('theme-toggle');
    const savedTheme = localStorage.getItem('theme');

    function applyThemeToHostApp(theme) {
        // Trimitem un semnal catre aplicatia Android gazda (daca este incarcat in WebView-ul local)
        try {
            if (window.AndroidInterface) {
                window.AndroidInterface.updateSystemUiTheme(theme);
            }
        } catch (e) {
            console.error("Nu pot apela AndroidInterface", e);
        }
    }

    if (savedTheme === 'light') {
        document.body.classList.add('light-mode');
        if (themeToggle) themeToggle.checked = false;
        applyThemeToHostApp('light');
    } else {
        if (themeToggle) themeToggle.checked = true; // Default dark
        applyThemeToHostApp('dark');
    }

    function updateLoginBtnColor() {
        const loginBtn = document.getElementById('login-btn');
        if (loginBtn) {
            const isLightMode = document.body.classList.contains('light-mode');
            let hex = colorHexMap[myBubbleColor];
            let textColor = 'white';

            if (myBubbleColor === 'white') {
                hex = isLightMode ? '#000000' : '#ffffff';
                textColor = isLightMode ? 'white' : 'black';
            }

            loginBtn.style.backgroundColor = hex;
            loginBtn.style.borderColor = hex;
            loginBtn.style.color = textColor;
            document.documentElement.style.setProperty('--dynamic-btn-color', hex);
        }
    }

    if (themeToggle) {
        themeToggle.addEventListener('change', (e) => {
            if (!e.target.checked) {
                document.body.classList.add('light-mode');
                localStorage.setItem('theme', 'light');
                applyThemeToHostApp('light');
            } else {
                document.body.classList.remove('light-mode');
                localStorage.setItem('theme', 'dark');
                applyThemeToHostApp('dark');
            }
            updateLoginBtnColor();
        });
    }

    // 1. CULORI
    const colorOptions = document.querySelectorAll('.color-option');
    colorOptions.forEach(option => {
        option.addEventListener('click', () => {
            if (colorLocked) return;
            colorOptions.forEach(o => o.classList.remove('selected'));
            option.classList.add('selected');
            myBubbleColor = option.dataset.color;
            updateLoginBtnColor();
        });
    });

    // Initialize first color
    updateLoginBtnColor();

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
        micBtn.addEventListener('mouseleave', () => { cancelRecording(); });

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
            stopRecording(); // Apelăm oricum stopRecording (care va ști dacă e cazul de anulare)
        });

        micBtn.addEventListener('touchcancel', (e) => {
            micBtn.style.transform = '';
            stopSparkler();
            cancelRecording();
        });
    }

    const disconnectBtn = document.getElementById('disconnect-btn');
    if (disconnectBtn) disconnectBtn.addEventListener('click', () => {
        isLoggedIn = false;
        if (socket) {
            socket.onclose = null; // Prevent auto-reconnect
            socket.close();
        }
        window.location.reload();
    });

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

    const backGenBtn = document.getElementById('back-to-general-btn');
    if (backGenBtn) backGenBtn.addEventListener('click', window.backToGeneralChat);

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
        distEl.innerText = t("searching_signal");
        distEl.classList.add('waiting');
        if(labelEl) labelEl.classList.add('hidden-label');
        return;
    }

    distEl.classList.remove('waiting');
    if(labelEl) labelEl.classList.remove('hidden-label');

    const dist = calculateDistance(myLat, myLon, targetLoc.lat, targetLoc.lon);
    let distText = (dist < 1000) ? Math.round(dist) + t("m_suffix") : (dist / 1000).toFixed(2) + t("km_suffix");
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
    if (isRecording || isRecordingRequested) return;
    isRecordingRequested = true;
    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        // Daca utilizatorul a ridicat degetul cat timp asteptam permisiunea:
        if (!isRecordingRequested) {
            stream.getTracks().forEach(track => track.stop());
            return;
        }

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
    } catch (err) {
        isRecordingRequested = false;
        alert(t("alert_mic"));
    }
}

function stopRecording() {
    isRecordingRequested = false;
    if (!isRecording) return;

    // Prevent sending if tapped too briefly (under 400ms)
    const duration = Date.now() - recordingStartTime;
    if (duration < 400) {
        isRecordingCancelled = true;
    }

    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
    }
    resetRecordingUI();
}
function cancelRecording() {
    isRecordingRequested = false;
    if (!isRecording) return;
    isRecordingCancelled = true;
    if (mediaRecorder && mediaRecorder.state !== 'inactive') { mediaRecorder.stop(); }
    resetRecordingUI();
}
function resetRecordingUI() { isRecording = false; clearInterval(recordingTimerInterval); document.getElementById('recording-overlay').classList.add('hidden'); document.getElementById('mic-btn').classList.remove('active'); document.getElementById('mic-btn').style.transform = ''; document.getElementById('rec-timer').innerText = "00:00"; }
function updateTimer() { const diff = Math.floor((Date.now() - recordingStartTime) / 1000); const m = Math.floor(diff / 60).toString().padStart(2, '0'); const s = (diff % 60).toString().padStart(2, '0'); document.getElementById('rec-timer').innerText = `${m}:${s}`; }

// ========================
// === CORE FUNCTIONS   ===
// ========================
function sendBuzz() { sendPayload({ type: 'buzz', sender: myName }); }
function handleBuzz(sender) {
    const body = document.getElementById('main-body');
    if(body) { body.classList.remove('shaking'); void body.offsetWidth; body.classList.add('shaking'); }
    renderSystemMessage(t("buzz_msg", { sender: sender }));
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
    addUserRow(container, myName + t("you_suffix"), myBubbleColor, true, myBattery);
    knownUsers.forEach((color, name) => {
        if (name !== myName) {
            const locInfo = userLocations.get(name);
            const batt = locInfo ? locInfo.battery : null;
            addUserRow(container, name, color, false, batt);
        }
    });
    if (knownUsers.size === 0) container.innerHTML += `<div style="padding:20px; text-align:center; color:var(--text-muted); font-size:13px;">${t("no_activity")}</div>`;
}

function addUserRow(container, name, color, isOnline, battery) {
    const div = document.createElement('div');
    div.className = 'user-item';
    let bg = colorHexMap[color] || "#555";
    const isLightMode = document.body.classList.contains('light-mode');

    let hex = bg;
    let textColor = 'white';
    if (color === 'white') {
        hex = isLightMode ? '#000000' : '#ffffff';
        textColor = isLightMode ? 'white' : 'black';
    }

    let battHtml = "";
    if (battery !== null && battery !== undefined) {
        let battColor = battery > 20 ? "#34c759" : "#ff3b30";
        battHtml = `
        <div style="display:flex; align-items:center; gap:4px; font-size:12px; color:var(--text-muted); margin-left:8px;">
            ${battery}%
            <div style="width:20px; height:10px; border:1px solid var(--text-muted); border-radius:2px; position:relative; box-sizing:border-box; padding:1px;">
                <div style="height:100%; width:${battery}%; background:${battColor}; border-radius:1px; transition:width 0.3s;"></div>
                <div style="position:absolute; right:-3px; top:2px; width:2px; height:4px; background:var(--text-muted); border-radius:0 1px 1px 0;"></div>
            </div>
        </div>`;
    }

    const unread = unreadCounts[name] || 0;
    const unreadBadge = unread > 0 ? `<span style="background:#ff3b30; color:white; border-radius:10px; padding:2px 6px; font-size:10px; font-weight:bold; margin-left:5px;">${unread}</span>` : '';

    let actionBtns = "";
    if (name !== myName + t("you_suffix")) {
        actionBtns = `
            <div class="user-actions">
                <button class="action-btn" onclick="openPrivateChat('${name}'); event.stopPropagation();">💬</button>
                <button class="action-btn" onclick="openCompass('${name}'); event.stopPropagation();">🧭</button>
            </div>
        `;
    }

    div.onclick = function() {
        if (name !== myName + t("you_suffix")) openPrivateChat(name);
    };

    div.innerHTML = `
        <div class="user-item-content">
            <div class="user-avatar" style="background:${hex}; color:${textColor}">
                ${name.charAt(0).toUpperCase()}
            </div>
            <div class="user-info">
                <div style="display:flex; align-items:center;">
                    <span class="user-name-list">${name}</span>
                    ${unreadBadge}
                </div>
                <div style="display:flex; align-items:center;">
                    <span class="user-status-list">${isOnline ? t("status_online") : t("status_recent")}</span>
                    ${battHtml}
                </div>
            </div>
        </div>
        ${actionBtns}
    `;
    container.appendChild(div);
}

function login() {
    const input = document.getElementById('username-input'); const name = input.value.trim();
    if (!name) { alert(t("alert_name")); return; }
    myName = name;
    if (socket && socket.readyState === WebSocket.OPEN) completeLogin();
    else { pendingLogin = true; renderSystemMessage(t("sys_connecting")); if (!socket || socket.readyState === WebSocket.CLOSED) connectServer(); }
}
function completeLogin() {
    if (isLoggedIn) return; isLoggedIn = true; pendingLogin = false; colorLocked = true;

    // Smooth transition from Login to Chat Screen
    const loginScreen = document.getElementById('login-screen');
    loginScreen.style.opacity = '0';
    loginScreen.style.transform = 'scale(1.05)';

    setTimeout(() => {
        loginScreen.classList.add('hidden');
        document.querySelector('.color-picker-container').style.display = 'none';

        const chatScreen = document.getElementById('chat-screen');
        chatScreen.classList.remove('hidden');
        chatScreen.style.animation = 'popIn 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275) forwards';

        document.getElementById('status-dot').classList.add('connected');
        sendPayload({ type: 'system', text: `${myName}${t("sys_connected")}` });
        startHeartbeat(); updateOnlineCounter();

        // Cerem permisiuni pentru senzori (ex. iOS 13+)
        if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
            DeviceOrientationEvent.requestPermission().catch(console.error);
        }

        // PORNIM LOCATION & BATTERY BROADCAST
        if (locationInterval) clearInterval(locationInterval);
        locationInterval = setInterval(() => {
            if (isLoggedIn && socket && socket.readyState === WebSocket.OPEN) {
                // Trimitem status (lat/lon poate fi 0 dacă nu are permisiune, dar bateria și online pot fi folositoare)
                socket.send(JSON.stringify({
                    type: 'location_update',
                    sender: myName,
                    lat: myLat,
                    lon: myLon,
                    battery: myBattery
                }));
            }
        }, 3000);
    }, 350);
}

function connectServer() {
    if (socket && socket.readyState === WebSocket.CONNECTING) return;
    if (reconnectTimeout) clearTimeout(reconnectTimeout);

    socket = new WebSocket(WS_URL);
    socket.onopen = () => { document.getElementById('status-dot').classList.add('connected'); if (myName && (pendingLogin || !isLoggedIn)) completeLogin(); };
    socket.onmessage = (event) => { if (event.data === "ping") return; try { handleData(JSON.parse(event.data)); } catch (e) { } };
    socket.onclose = () => {
        document.getElementById('status-dot').classList.remove('connected');
        renderSystemMessage(t("sys_lost"));
        stopHeartbeat();
        isLoggedIn = false;
        if (reconnectTimeout) clearTimeout(reconnectTimeout);
        reconnectTimeout = setTimeout(connectServer, 3000);
    };
}
function startHeartbeat() { stopHeartbeat(); heartbeatInterval = setInterval(() => { if (socket && socket.readyState === WebSocket.OPEN) socket.send("ping"); }, 10000); }
function stopHeartbeat() { if (heartbeatInterval) { clearInterval(heartbeatInterval); heartbeatInterval = null; } }
async function sendPayload(data) {
    if (socket && socket.readyState === WebSocket.OPEN) {
        data.sender = myName;
        data.color = myBubbleColor;
        data.recipient = activeChat;

        if (roomCryptoKey) {
            const innerType = data.type;
            const dataStr = JSON.stringify(data);
            const encrypted = await encryptData(dataStr);
            const wrapper = {
                type: 'encrypted',
                innerType: innerType,
                payload: encrypted
            };
            socket.send(JSON.stringify(wrapper));
        } else {
            socket.send(JSON.stringify(data));
        }
    }
}
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
async function handleData(data) {
    if (data.type === 'encrypted') {
        const decryptedStr = await decryptData(data.payload);
        try {
            data = JSON.parse(decryptedStr);
        } catch (e) {
            return;
        }
    }

    if (data.type === 'location_update') {
        if (data.sender && data.sender !== myName) {
            userLocations.set(data.sender, {
                lat: data.lat,
                lon: data.lon,
                battery: data.battery
            });
            if (targetUserForCompass === data.sender) updateCompassUI();

            // Daca modalul este deschis, ii dam un refresh "tăcut" ca să apară/modifice bateria
            const modal = document.getElementById('users-modal');
            if (modal && modal.classList.contains('open')) {
                renderUserList();
            }
        }
        return;
    }
    if (data.sender && data.sender !== myName) { if (!knownUsers.has(data.sender)) { knownUsers.set(data.sender, data.color || "blue"); updateOnlineCounter(); } else { knownUsers.set(data.sender, data.color || "blue"); } }
    switch (data.type) {
        case 'chat': renderMessage(data); break;
        case 'image': renderImageMessage(data); break;
        case 'audio': renderAudioMessage(data); break;
        case 'buzz':
            const isGeneralBuzz = !data.recipient || data.recipient === 'general' || data.recipient === 'all';
            if (!isGeneralBuzz && data.recipient !== myName) break;
            handleBuzz(data.sender);
            break;
        case 'system':
            const suffixRo = " s-a conectat.";
            const suffixEn = " joined.";
            if (data.text.includes(suffixRo) || data.text.includes(suffixEn)) {
                const name = data.text.replace(suffixRo, "").replace(suffixEn, "");
                if(name && name !== myName) { knownUsers.set(name, "blue"); updateOnlineCounter(); }
            }
            renderSystemMessage(data.text);
            break;
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
        seenLabel.textContent = (currentText === "") ? `${t("seen_by")}${who}` : `${currentText}, ${who}`;
    }
}
function updateOnlineCounter() { const el = document.getElementById('online-count'); const count = 1 + knownUsers.size; if (el) el.textContent = t("online_count", {count: count}); }
function attachSwipeListeners(element, messageData) {
    let startX = 0; let startY = 0; let currentX = 0; let isSwiping = false; let hasTriggered = false; let isVertical = false;

    // Create reply icon container
    const replyIcon = document.createElement('div');
    replyIcon.innerHTML = `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 14 4 9 9 4"></polyline><path d="M20 20v-7a4 4 0 0 0-4-4H4"></path></svg>`;
    replyIcon.className = 'swipe-reply-icon';
    element.appendChild(replyIcon);

    element.addEventListener('touchstart', (e) => {
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        isSwiping = false;
        hasTriggered = false;
        isVertical = false;
        const bubble = element.querySelector('.bubble');
        if (bubble) bubble.style.transition = 'none';
        replyIcon.style.transition = 'none';
    }, {passive: true});

    element.addEventListener('touchmove', (e) => {
        if (isVertical) return;
        currentX = e.touches[0].clientX;
        const currentY = e.touches[0].clientY;
        const diffX = currentX - startX;
        const diffY = currentY - startY;

        // Detect if scrolling vertically
        if (!isSwiping && Math.abs(diffY) > Math.abs(diffX)) {
            isVertical = true;
            return;
        }

        if (diffX > 5 && diffX < 120) {
            isSwiping = true;
            const bubble = element.querySelector('.bubble');
            if (bubble) bubble.style.transform = `translateX(${diffX}px)`;

            // Icon animation
            const progress = Math.min(diffX / 60, 1);
            replyIcon.style.opacity = progress;
            replyIcon.style.transform = `scale(${progress})`;

            if (diffX > 60 && !hasTriggered) {
                if (navigator.vibrate) navigator.vibrate(20);
                hasTriggered = true;
                replyIcon.style.color = 'var(--dynamic-btn-color, #0084ff)';
            } else if (diffX <= 60) {
                hasTriggered = false;
                replyIcon.style.color = 'var(--text-muted)';
            }
        }
    }, {passive: true});

    element.addEventListener('touchend', () => {
        if (!isSwiping) return;
        const diff = currentX - startX;

        const bubble = element.querySelector('.bubble');
        if (bubble) {
            bubble.style.transition = 'transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)';
            bubble.style.transform = 'translateX(0)';
        }

        replyIcon.style.transition = 'opacity 0.3s, transform 0.3s';
        replyIcon.style.opacity = '0';
        replyIcon.style.transform = 'scale(0)';

        if (diff > 60) triggerReply(messageData);
        startX = 0; startY = 0; currentX = 0; isSwiping = false;
    });

    element.addEventListener('dblclick', () => { triggerReply(messageData); });
}
function triggerReply(messageData) {
    let replyText = messageData.text;
    if (messageData.type === 'image') replyText = t("reply_img");
    if (messageData.type === 'audio') replyText = t("reply_audio");
    replyingTo = { id: messageData.id, sender: messageData.sender, text: replyText };
    document.getElementById('reply-bar').classList.remove('hidden'); document.getElementById('reply-target-name').textContent = messageData.sender; document.getElementById('reply-target-text').textContent = replyText; document.getElementById('msg-input').focus();
}
function cancelReply() { replyingTo = null; document.getElementById('reply-bar').classList.add('hidden'); }
function scrollToMessage(msgId) { const el = document.getElementById(msgId); if(el) { el.scrollIntoView({ behavior: 'smooth', block: 'center' }); el.classList.add('highlight-message'); setTimeout(() => el.classList.remove('highlight-message'), 1500); } }

function applyGrouping(row, data, chatGroup) {
    const isConsecutive = lastMessageSenders[chatGroup] === data.sender;
    if (isConsecutive && lastMessageRows[chatGroup]) {
        row.classList.add('consecutive');
        if (lastMessageRows[chatGroup].classList.contains('group-end')) {
            lastMessageRows[chatGroup].classList.remove('group-end');
            lastMessageRows[chatGroup].classList.add('group-middle');
        } else if (lastMessageRows[chatGroup].classList.contains('lone-message')) {
            lastMessageRows[chatGroup].classList.remove('lone-message');
            lastMessageRows[chatGroup].classList.add('group-start');
        }
        row.classList.add('group-end');
    } else {
        row.classList.add('lone-message');
    }
    lastMessageSenders[chatGroup] = data.sender;
    lastMessageRows[chatGroup] = row;
    return isConsecutive;
}

function isEmojiOnly(str) {
    if (!str || str.trim().length === 0) return false;
    const emojiRegex = /^(\p{Emoji_Presentation}|\p{Emoji}\uFE0F|\s)+$/u;
    return emojiRegex.test(str);
}

function renderMessage(data) {
    if (!data.id) data.id = generateId();
    const isGeneral = !data.recipient || data.recipient === 'general' || data.recipient === 'all';
    const chatGroup = isGeneral ? 'general' : (data.sender === myName ? data.recipient : data.sender);
    if (!isGeneral && data.sender !== myName && data.recipient !== myName) return;

    const list = document.getElementById('messages-list'); const isMe = data.sender.trim() === myName.trim(); const color = data.color || "blue";
    const row = document.createElement('div'); row.className = `message-row ${isMe ? 'mine' : 'theirs'}`; row.id = data.id; row.dataset.chatGroup = chatGroup;
    if (activeChat !== chatGroup) {
        row.classList.add('hidden-chat');
        if (!isMe) { unreadCounts[chatGroup] = (unreadCounts[chatGroup] || 0) + 1; updateUnreadBadges(); }
    }
    attachSwipeListeners(row, data);
    const isConsecutive = applyGrouping(row, data, chatGroup);
    let content = ""; if (!isMe && !isConsecutive) content += `<div class="sender-name clickable" onclick="openPrivateChat('${data.sender}')">${data.sender}</div>`;

    const emojiOnly = isEmojiOnly(data.text);
    content += `<div class="bubble ${color} ${emojiOnly ? 'emoji-only' : ''}">`;
    if (data.replyTo) { const origId = data.replyTo.id; content += `<div class="reply-preview-in-message" onclick="scrollToMessage('${origId}')"><span class="reply-from-name">${data.replyTo.sender}</span><span class="reply-original-text">${data.replyTo.text}</span></div>`; }
    content += `${data.text}</div>`; row.innerHTML = content; list.appendChild(row); requestAnimationFrame(() => { list.scrollTop = list.scrollHeight; });
    if (!isMe) { if (document.hidden) { unseenMsgQueue.add(data.id); } else { sendSeen(data.id); } }
}
function renderImageMessage(data) {
    if (!data.id) data.id = generateId();
    const isGeneral = !data.recipient || data.recipient === 'general' || data.recipient === 'all';
    const chatGroup = isGeneral ? 'general' : (data.sender === myName ? data.recipient : data.sender);
    if (!isGeneral && data.sender !== myName && data.recipient !== myName) return;

    const list = document.getElementById('messages-list'); const isMe = data.sender.trim() === myName.trim(); const color = data.color || "blue";
    const row = document.createElement('div'); row.className = `message-row ${isMe ? 'mine' : 'theirs'}`; row.id = data.id; row.dataset.chatGroup = chatGroup;
    if (activeChat !== chatGroup) {
        row.classList.add('hidden-chat');
        if (!isMe) { unreadCounts[chatGroup] = (unreadCounts[chatGroup] || 0) + 1; updateUnreadBadges(); }
    }
    attachSwipeListeners(row, data);
    const isConsecutive = applyGrouping(row, data, chatGroup);
    let content = ""; if (!isMe && !isConsecutive) content += `<div class="sender-name clickable" onclick="openPrivateChat('${data.sender}')">${data.sender}</div>`;
    content += `<div class="bubble ${color} has-image">`;
    if (data.replyTo) { const origId = data.replyTo.id; content += `<div class="reply-preview-in-message" onclick="scrollToMessage('${origId}')"><span class="reply-from-name">${data.replyTo.sender}</span><span class="reply-original-text">${data.replyTo.text}</span></div>`; }
    content += `<img src="${data.image}" class="chat-image" alt="Imagine" onclick="openImage('${data.image}')">`; content += `</div>`; row.innerHTML = content; list.appendChild(row); requestAnimationFrame(() => { list.scrollTop = list.scrollHeight; });
    if (!isMe) { if (document.hidden) { unseenMsgQueue.add(data.id); } else { sendSeen(data.id); } }
}
function renderAudioMessage(data) {
    if (!data.id) data.id = generateId();
    const isGeneral = !data.recipient || data.recipient === 'general' || data.recipient === 'all';
    const chatGroup = isGeneral ? 'general' : (data.sender === myName ? data.recipient : data.sender);
    if (!isGeneral && data.sender !== myName && data.recipient !== myName) return;

    const list = document.getElementById('messages-list'); const isMe = data.sender.trim() === myName.trim(); const color = data.color || "blue";
    const row = document.createElement('div'); row.className = `message-row ${isMe ? 'mine' : 'theirs'}`; row.id = data.id; row.dataset.chatGroup = chatGroup;
    if (activeChat !== chatGroup) {
        row.classList.add('hidden-chat');
        if (!isMe) { unreadCounts[chatGroup] = (unreadCounts[chatGroup] || 0) + 1; updateUnreadBadges(); }
    }
    attachSwipeListeners(row, data);
    const isConsecutive = applyGrouping(row, data, chatGroup);
    let content = ""; if (!isMe && !isConsecutive) content += `<div class="sender-name clickable" onclick="openPrivateChat('${data.sender}')">${data.sender}</div>`;
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
function renderSystemMessage(text) { const list = document.getElementById('messages-list'); const div = document.createElement('div'); div.className = 'system-msg'; div.innerText = text; div.dataset.chatGroup = 'general'; if (activeChat !== 'general') div.classList.add('hidden-chat'); list.appendChild(div); list.scrollTop = list.scrollHeight; }
window.startPulsing = function() { const btn = document.getElementById('login-btn'); if(btn) { btn.innerText="Conectare în Mesh"; btn.classList.add('pulsing-button-mode'); } };
window.stopPulsing = function() { const btn = document.getElementById('login-btn'); if(btn) { btn.innerText="Conectare"; btn.classList.remove('pulsing-button-mode'); } };