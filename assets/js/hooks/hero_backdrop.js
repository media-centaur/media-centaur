// HeroBackdrop — paints a page hero backdrop from a decoded-bitmap cache.
//
// Every live navigation rebuilds the page DOM, so an `<img>` hero is decoded
// again on every return — ~50 ms of raster-worker time for a 3840×2160
// master, during which Chromium paints the page without it and fills the
// picture in afterwards. `decoding="sync"` does not help: on the GPU raster
// path an image this large is decoded asynchronously regardless.
//
// This module keeps the decoded `ImageBitmap` in JavaScript, which survives
// navigation, and draws it onto a `<canvas>` in the hero slot from the hook's
// `mounted` — the same task as the DOM patch, so a cache hit lands in the
// mount frame. `<canvas>` is a replaced element like `<img>`, so the page CSS
// (`object-fit: cover`, `object-position`) applies unchanged.
//
// Expected shape (rendered by `Components.HeroBackdrop.hero_backdrop/1`):
//   <canvas id="hero-backdrop" phx-hook="HeroBackdrop" data-src="/media-images/…/backdrop.jpg">
//
// `data-src` is the cache key: the master's URL. The root layout marks the
// same URL in a `<meta name="hero-backdrop">` and app.js pre-decodes it at
// idle, so the first visit is warm too. Cache capacity is two: the two
// assembled pages, Home and Discovery, each carry one backdrop (UIDR-033,
// amended 2026-11-01), so moving between them keeps both bitmaps instead of
// re-decoding on every return.
//
// The bytes fetched for a key are a derivative sized to the display
// (`fetchUrl`): the key plus `?w=`, the width that covers the display at the
// backdrop's 16:9. Only the browser knows the display, so the server cannot
// size the URL and the layout carries no prefetch for it. ImageServer snaps
// the width up its ladder and never upscales: the TV app's 1920 px page gets
// the 1920×1080 tier (a quarter of the master's bytes and decode), a 4K
// desktop or a portrait phone — where the height binds under `object-fit:
// cover` — asks beyond the ladder and gets the master. A decoded bitmap is
// then kept no larger than the display can show (`fitToScreen`): ~33 MB for
// a 4K master on a 4K screen, ~8 MB on the TV. The hero rotates and a `?v=`
// bump changes the key — either way the outgoing bitmap is never asked for
// again, so evicting it is the right move, and invalidation is the key
// itself.
//
// `data-hero-state` reports the slot's state — `pending` (decoding),
// `drawn`, or `failed` — for tests and runtime probes; nothing styles it.

// The largest the hero can be drawn, in device pixels: the screen, or the
// viewport when that is larger — headless Chromium reports an 800×600-class
// screen whatever its window, and screenshot captures must keep a full hero.
// Browser zoom trades CSS pixels for devicePixelRatio, so the products are
// device resolution either way.
export function displaySize(screenSize, viewport, ratio) {
  return {
    width: Math.round(Math.max(screenSize.width, viewport.width) * ratio),
    height: Math.round(Math.max(screenSize.height, viewport.height) * ratio)
  }
}

function currentDisplaySize() {
  return displaySize(
    { width: screen.width, height: screen.height },
    { width: window.innerWidth, height: window.innerHeight },
    window.devicePixelRatio || 1
  )
}

// A decoded bitmap no larger than the screen can show. The hero covers its
// slot (`object-fit: cover`) and the slot is never larger than the screen, so
// the picture is scaled to cover the screen and only ever down: a 4K master
// on a 4K screen is kept as decoded, a smaller picture is never enlarged. The
// TV app draws a 1080p page, where a 4K master held at full size spent three
// quarters of its memory on pixels never shown.
export async function fitToScreen(bitmap, screenSize, resize = (source, options) => createImageBitmap(source, options)) {
  const scale = Math.max(screenSize.width / bitmap.width, screenSize.height / bitmap.height)
  if (scale >= 1) return bitmap
  const fitted = await resize(bitmap, {
    resizeWidth: Math.round(bitmap.width * scale),
    resizeHeight: Math.round(bitmap.height * scale),
    resizeQuality: "high"
  })
  bitmap.close()
  return fitted
}

// The URL fetched for a cache key: ImageServer's `?w=` derivative at the
// width that covers the display at 16:9, the shape the pipeline fits every
// backdrop master into. The server never upscales, so asking wide is safe.
export function fetchUrl(key, display) {
  const width = Math.max(display.width, Math.ceil((display.height * 16) / 9))
  const url = new URL(key, "http://hero.invalid")
  url.searchParams.set("w", String(width))
  return url.pathname + url.search
}

async function decodeUrl(key) {
  const display = currentDisplaySize()
  const response = await fetch(fetchUrl(key, display))
  if (!response.ok) throw new Error(`hero backdrop ${key}: HTTP ${response.status}`)
  return fitToScreen(await createImageBitmap(await response.blob()), display)
}

// LRU keyed by URL. `get` promotes; `load` dedupes in-flight decodes and
// closes the bitmap it evicts so its GPU memory is released promptly.
export function createBitmapCache({ capacity = 1, decode = decodeUrl } = {}) {
  const entries = new Map()
  const inflight = new Map()

  function get(url) {
    const bitmap = entries.get(url)
    if (bitmap) {
      entries.delete(url)
      entries.set(url, bitmap)
    }
    return bitmap
  }

  function put(url, bitmap) {
    entries.set(url, bitmap)
    while (entries.size > capacity) {
      const [oldestUrl, oldest] = entries.entries().next().value
      entries.delete(oldestUrl)
      if (typeof oldest.close === "function") oldest.close()
    }
  }

  function load(url) {
    const hit = get(url)
    if (hit) return Promise.resolve(hit)
    if (inflight.has(url)) return inflight.get(url)
    const loading = decode(url).then(
      (bitmap) => {
        inflight.delete(url)
        put(url, bitmap)
        return bitmap
      },
      (error) => {
        inflight.delete(url)
        throw error
      }
    )
    inflight.set(url, loading)
    return loading
  }

  return {
    get,
    load,
    has: (url) => entries.has(url),
    get size() { return entries.size }
  }
}

function paint(canvas, bitmap) {
  if (canvas.width !== bitmap.width) canvas.width = bitmap.width
  if (canvas.height !== bitmap.height) canvas.height = bitmap.height
  canvas.getContext("2d").drawImage(bitmap, 0, 0)
  canvas.dataset.heroState = "drawn"
}

export function createHeroBackdropHook(cache) {
  return {
    mounted() {
      this._paint()
    },

    // Fires when a patch touched this element: a new `data-src` (hero
    // rotation, `?v=` bump), or morphdom syncing the server markup and
    // dropping the client-set width/height, which blanks the canvas.
    // Repainting from cache is one drawImage, so always repaint.
    updated() {
      this._paint()
    },

    _paint() {
      const url = this.el.dataset.src
      if (!url) return
      const hit = cache.get(url)
      if (hit) {
        paint(this.el, hit)
        return
      }
      this.el.dataset.heroState = "pending"
      cache.load(url).then(
        (bitmap) => {
          // The slot may have moved on (new src) or been torn down while
          // decoding; a stale bitmap must not overwrite the current one.
          if (this.el.isConnected === false || this.el.dataset.src !== url) return
          paint(this.el, bitmap)
        },
        () => {
          if (this.el.dataset.src === url) this.el.dataset.heroState = "failed"
        }
      )
    }
  }
}

// Sequential so the warm-up never competes with itself; a failure is
// skipped, not fatal — the hook's miss path covers that URL on first visit.
export function warmHeroBackdrops(urls, cache) {
  return urls.reduce(
    (previous, url) => previous.then(() => cache.load(url).catch(() => {})),
    Promise.resolve()
  )
}

export const heroBitmapCache = createBitmapCache({ capacity: 2 })
export const HeroBackdrop = createHeroBackdropHook(heroBitmapCache)
