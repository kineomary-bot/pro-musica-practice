const SHELL_CACHE = 'pro-musica-shell-v17';
const OFFLINE_CACHE = 'pro-musica-offline-songs-v1';
const SHELL = ['./', './index.html', './pieces.json', './manifest.webmanifest', './icon-192.png', './icon-512.png', './apple-touch-icon.png', './choir-logo.svg'];
const OPTIONAL_BOARD_DATA = ['./announcements.json', './events.json'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(SHELL_CACHE).then(async cache => {
    await cache.addAll(SHELL);
    await Promise.all(OPTIONAL_BOARD_DATA.map(asset => cache.add(asset).catch(() => null)));
  }).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('pro-musica-shell-') && k !== SHELL_CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // Song files explicitly downloaded by the singer are kept in a separate cache.
  // Serve these first so audio and PDFs remain available without a connection.
  event.respondWith((async () => {
    const saved = await caches.open(OFFLINE_CACHE);
    const savedResponse = await saved.match(req, {ignoreSearch: true});
    if (savedResponse) return savedResponse;
    if (['/pieces.json', '/announcements.json', '/events.json'].some(path => url.pathname.endsWith(path))) {
      const shell = await caches.open(SHELL_CACHE);
      try {
        const response = await fetch(req);
        if (response.ok) {
          await shell.put(req, response.clone());
          return response;
        }
        // Prefer the last known-good data if a partial deployment responds with 404/5xx.
        const cached = await shell.match(req);
        if (cached && (response.status === 404 || response.status >= 500)) return cached;
        return response;
      } catch (error) {
        const cached = await shell.match(req);
        if (cached) return cached;
        throw error;
      }
    }
    if (req.mode === 'navigate' || /\.(?:html|webmanifest|png)$/.test(url.pathname)) {
      const shell = await caches.open(SHELL_CACHE);
      const cached = await shell.match(req);
      if (cached) return cached;
      const response = await fetch(req);
      if (response.ok) await shell.put(req, response.clone());
      return response;
    }
    return fetch(req);
  })());
});
