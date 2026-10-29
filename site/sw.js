const SHELL_CACHE = 'pro-musica-shell-v15';
const OFFLINE_CACHE = 'pro-musica-offline-songs-v1';
const SHELL = ['./', './index.html', './pieces.json', './manifest.webmanifest', './icon-192.png', './icon-512.png', './apple-touch-icon.png', './choir-logo.svg', './announcements.json', './events.json'];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(SHELL_CACHE).then(cache => cache.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('pro-musica-shell-') && k !== SHELL_CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
async function respondWithByteRange(request, response) {
  const range = request.headers.get('range');
  if (!range || response.status !== 200) return response;
  const contentType = (response.headers.get('content-type') || '').toLowerCase();
  if (!contentType.startsWith('audio/') && !contentType.includes('application/pdf')) return response;

  const match = /^bytes=(\\d*)-(\\d*)$/.exec(range.trim());
  if (!match) return response;

  const body = await response.arrayBuffer();
  const size = body.byteLength;
  let start;
  let end;
  if (match[1] === '') {
    const suffixLength = Number(match[2]);
    if (!suffixLength || !size) return new Response(null, {status: 416, headers: {'Content-Range': 'bytes */' + size}});
    start = Math.max(0, size - suffixLength);
    end = size - 1;
  } else {
    start = Number(match[1]);
    end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1);
  }

  if (!size || start >= size || start < 0 || end < start) {
    return new Response(null, {status: 416, headers: {'Content-Range': 'bytes */' + size, 'Accept-Ranges': 'bytes'}});
  }

  const headers = new Headers(response.headers);
  headers.delete('Content-Encoding');
  headers.set('Accept-Ranges', 'bytes');
  headers.set('Content-Range', 'bytes ' + start + '-' + end + '/' + size);
  headers.set('Content-Length', String(end - start + 1));
  return new Response(body.slice(start, end + 1), {status: 206, statusText: 'Partial Content', headers});
}

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // Song files explicitly downloaded by the singer are kept in a separate cache.
  // Honour byte-range requests for cached media so seeking works online and offline.
  event.respondWith((async () => {
    const saved = await caches.open(OFFLINE_CACHE);
    const savedResponse = await saved.match(req, {ignoreSearch: true});
    if (savedResponse) return respondWithByteRange(req, savedResponse);
    if (['/pieces.json', '/announcements.json', '/events.json'].some(path => url.pathname.endsWith(path))) {
      try {
        const response = await fetch(req);
        if (response.ok) { const shell = await caches.open(SHELL_CACHE); await shell.put(req, response.clone()); }
        return response;
      } catch (error) {
        const shell = await caches.open(SHELL_CACHE);
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
