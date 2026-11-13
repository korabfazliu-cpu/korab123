// Digital HR service worker: shows push notifications and opens the app when one is tapped.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { body: e.data && e.data.text() }; }
  const title = d.title || 'Digital HR';
  e.waitUntil(self.registration.showNotification(title, {
    body: d.body || 'Keni një njoftim të ri.',
    icon: '/icon-192.png',
    badge: '/icon-192.png',
    tag: d.id || undefined,
    data: { url: d.url || '/' }
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || '/';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if ('focus' in c) { c.navigate ? c.navigate(url).catch(() => {}) : 0; return c.focus(); } }
    return self.clients.openWindow(url);
  }));
});
