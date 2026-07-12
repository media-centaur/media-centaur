// Media Centaur's UI typically runs beneath a fullscreen video player for
// long stretches — playback is the product's main activity. Chromium
// backgrounds occluded windows: timers are throttled or frozen, Phoenix
// heartbeats stop, and the server drops the LiveView socket. Without help,
// the page shown at player-close is a stale pre-playback snapshot until the
// throttled reconnect backoff happens to fire.
//
// This forces an immediate reconnect the moment the page is user-visible
// again (visibilitychange / window focus / pageshow). `connect()` is a no-op
// while a transport exists, so the guard plus Phoenix's own idempotence make
// repeated triggers safe.
export function installReconnectOnVisible(liveSocket, doc = document, win = window) {
  const reconnectIfDead = () => {
    if (doc.visibilityState === "visible" && !liveSocket.isConnected()) {
      liveSocket.connect()
    }
  }

  doc.addEventListener("visibilitychange", reconnectIfDead)
  win.addEventListener("focus", reconnectIfDead)
  win.addEventListener("pageshow", reconnectIfDead)
}
