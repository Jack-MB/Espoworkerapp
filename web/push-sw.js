self.addEventListener('push', function(event) {
  if (!event.data) return;

  let data = {};
  try {
    data = event.data.json();
  } catch (e) {
    data = { title: 'Neue Benachrichtigung', body: event.data.text() };
  }

  const targetUrl = data.url || '/';

  const options = {
    body: data.body || '',
    icon: data.icon || '/favicon.png',
    badge: '/favicon.png',
    tag: data.tag || 'mb-worker-notification',
    renotify: true,
    data: {
      url: targetUrl,
      notificationId: data.notificationId || null,
      type: data.type || null
    }
  };

  event.waitUntil(
    self.registration.showNotification(data.title || 'MB-SCC', options)
  );
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();

  const notifData = event.notification.data || {};
  const targetUrl = typeof notifData === 'string' ? notifData : (notifData.url || '/');

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      // Check if there is already an open window from our origin
      for (let i = 0; i < clientList.length; i++) {
        const client = clientList[i];
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          // Post message to the app so Flutter can react immediately
          client.postMessage({
            type: 'NOTIFICATION_CLICK',
            url: targetUrl,
            data: notifData
          });
          // Update URL hash / navigate if needed and bring window to front
          if ('navigate' in client && targetUrl !== '/') {
            client.navigate(targetUrl);
          }
          return client.focus();
        }
      }

      // If no window is open, open a new one
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});

