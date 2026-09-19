function urlBase64ToUint8Array(base64String) {
  var padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  var base64 = (base64String + padding)
    .replace(/\-/g, '+')
    .replace(/_/g, '/');

  var rawData = window.atob(base64);
  var outputArray = new Uint8Array(rawData.length);

  for (var i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

async function subscribeToWebPush(vapidPublicKey) {
  try {
    if (!('serviceWorker' in navigator)) {
      console.warn('Service Worker not supported');
      return JSON.stringify({ error: 'Service Worker wird in diesem Browser nicht unterstützt.' });
    }
    if (!('PushManager' in window)) {
      console.warn('PushManager not supported');
      return JSON.stringify({ error: 'Push-Benachrichtigungen werden in diesem Browser nicht unterstützt.' });
    }

    // Register the custom push service worker
    const registration = await navigator.serviceWorker.register('/push-sw.js', { scope: '/' });
    await navigator.serviceWorker.ready;

    // Ask for permission
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') {
      console.log('Push permission not granted:', permission);
      return JSON.stringify({ error: 'Benachrichtigungsberechtigung wurde nicht erteilt (' + permission + ').' });
    }

    // Convert VAPID key to Uint8Array BufferSource required by PushManager
    const applicationServerKey = urlBase64ToUint8Array(vapidPublicKey);

    // Subscribe (or retrieve existing active subscription)
    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: applicationServerKey
      });
    }

    return JSON.stringify(subscription);
  } catch (e) {
    console.error("WebPush Error:", e);
    return JSON.stringify({ error: 'WebPush Fehler: ' + (e.message || String(e)) });
  }
}

function isIosStandalone() {
  const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!isIos) return true; // It's not iOS, so we don't care about standalone status for the tutorial
  
  const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  return isStandalone;
}

function isIos() {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

function getNotificationPermission() {
  if (!('Notification' in window)) {
    return 'unsupported';
  }
  return Notification.permission;
}

// Listen for service worker notification click messages
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.addEventListener('message', function(event) {
    if (event.data && event.data.type === 'NOTIFICATION_CLICK') {
      const url = event.data.url;
      window.dispatchEvent(new CustomEvent('mb_notification_click', { detail: url }));
    }
  });
}
