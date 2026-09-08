// AirChat service worker.
//
// Network-first for everything: the room is a live app and a stale index.html
// would break the WebSocket handshake, so the cache is only a fallback for a
// guest who opens the link with no connection to the host at all.
const CACHE_NAME = 'airchat-cache-v3';

// Kept warm so a cold offline open still paints the UI. Every entry here is a
// static asset of the shared bundle (style.css, app.js, the iOS bridge and the
// install guide are the same files on Android and iOS).
const urlsToCache = [
    '/index.html',
    '/style.css',
    '/app.js',
    '/airchat-bridge.js',
    '/install.html',
    '/manifest.json'
];

self.addEventListener('install', event => {
    self.skipWaiting();
    event.waitUntil(
        caches.open(CACHE_NAME).then(cache =>
            // Not addAll(): one missing file must not leave the whole cache empty.
            Promise.all(urlsToCache.map(url =>
                fetch(url).then(res => (res && res.ok) ? cache.put(url, res.clone()) : null)
                      .catch(() => null)
            ))
        )
    );
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(cacheNames => Promise.all(
            cacheNames.filter(name => name !== CACHE_NAME).map(name => caches.delete(name))
        ))
    );
    self.clients.claim();
});

self.addEventListener('fetch', event => {
    const req = event.request;

    // Only plain GETs. WebSocket upgrades are never a fetch the SW should touch,
    // and anything dynamic (POST /api/*, /download-app/*) must hit the server.
    if (req.method !== 'GET' || req.mode === 'websocket') return;

    const url = new URL(req.url);
    if (url.origin !== self.location.origin) return;          // never proxy someone else

    event.respondWith(
        fetch(req).then(response => {
            if (response && response.ok && response.type === 'basic') {
                const copy = response.clone();
                caches.open(CACHE_NAME).then(cache => cache.put(req, copy));
            }
            return response;
        }).catch(() => caches.match(req).then(hit =>
            hit || (url.pathname === '/' ? caches.match('/index.html') : Response.error())
        ))
    );
});
