import { describe, expect, test } from "bun:test"
import { createBitmapCache, createHeroBackdropHook, displaySize, fitToScreen, warmHeroBackdrops } from "./hero_backdrop"

// A decoded bitmap stand-in: the cache only needs width/height and close().
function fakeBitmap(name, width = 3840, height = 2160) {
  return { name, width, height, closed: false, close() { this.closed = true } }
}

// Controllable decoder: resolves each URL by hand so tests can interleave
// hits, misses, and in-flight loads deterministically.
function fakeDecoder() {
  const pending = new Map()
  const calls = []
  const decode = (url) => {
    calls.push(url)
    return new Promise((resolve, reject) => pending.set(url, { resolve, reject }))
  }
  const resolve = (url, bitmap = fakeBitmap(url)) => {
    pending.get(url).resolve(bitmap)
    pending.delete(url)
    return bitmap
  }
  const reject = (url) => {
    pending.get(url).reject(new Error("decode failed"))
    pending.delete(url)
  }
  return { decode, resolve, reject, calls }
}

// The hero slot: a canvas whose 2D context records draws. `dataset` mirrors
// the DOM's, `width`/`height` start at the canvas default (300x150).
function fakeCanvas(src) {
  const draws = []
  return {
    dataset: { src },
    width: 300,
    height: 150,
    isConnected: true,
    draws,
    getContext() {
      return { drawImage: (bitmap, x, y) => draws.push({ bitmap, x, y }) }
    }
  }
}

function mountHook(hook, el) {
  const instance = Object.create(hook)
  instance.el = el
  instance.mounted()
  return instance
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0))

describe("createBitmapCache", () => {
  test("get misses until load has resolved, then hits without decoding again", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })

    expect(cache.get("/a")).toBeUndefined()
    const loading = cache.load("/a")
    const bitmap = decoder.resolve("/a")
    expect(await loading).toBe(bitmap)
    expect(cache.get("/a")).toBe(bitmap)

    await cache.load("/a")
    expect(decoder.calls).toEqual(["/a"])
  })

  test("concurrent loads of one URL share a single decode", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })

    const first = cache.load("/a")
    const second = cache.load("/a")
    decoder.resolve("/a")

    expect(await first).toBe(await second)
    expect(decoder.calls).toEqual(["/a"])
  })

  test("evicts the least recently used bitmap past capacity and closes it", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 2, decode: decoder.decode })

    const a = cache.load("/a"); const bitmapA = decoder.resolve("/a"); await a
    const b = cache.load("/b"); decoder.resolve("/b"); await b
    // Touch /a so /b becomes the oldest.
    cache.get("/a")
    const c = cache.load("/c"); decoder.resolve("/c"); await c

    expect(cache.has("/a")).toBe(true)
    expect(cache.has("/b")).toBe(false)
    expect(cache.has("/c")).toBe(true)
    expect(bitmapA.closed).toBe(false)
    expect(cache.size).toBe(2)
  })

  test("a failed decode is not cached and can be retried", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 2, decode: decoder.decode })

    const failing = cache.load("/a")
    decoder.reject("/a")
    await expect(failing).rejects.toThrow("decode failed")
    expect(cache.has("/a")).toBe(false)

    const retry = cache.load("/a")
    decoder.resolve("/a")
    await retry
    expect(cache.has("/a")).toBe(true)
    expect(decoder.calls).toEqual(["/a", "/a"])
  })
})

describe("HeroBackdrop hook", () => {
  test("a cache hit paints in the same task as mounted, sized to the bitmap", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })
    const loading = cache.load("/hero.jpg")
    const bitmap = decoder.resolve("/hero.jpg", fakeBitmap("hero", 3840, 2160))
    await loading

    const el = fakeCanvas("/hero.jpg")
    mountHook(createHeroBackdropHook(cache), el)

    expect(el.draws).toEqual([{ bitmap, x: 0, y: 0 }])
    expect(el.width).toBe(3840)
    expect(el.height).toBe(2160)
    expect(el.dataset.heroState).toBe("drawn")
  })

  test("a cache miss decodes, then paints once the bitmap arrives", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })
    const el = fakeCanvas("/hero.jpg")

    mountHook(createHeroBackdropHook(cache), el)
    expect(el.draws).toEqual([])
    expect(el.dataset.heroState).toBe("pending")

    const bitmap = decoder.resolve("/hero.jpg")
    await flush()

    expect(el.draws).toEqual([{ bitmap, x: 0, y: 0 }])
    expect(el.dataset.heroState).toBe("drawn")
    expect(cache.has("/hero.jpg")).toBe(true)
  })

  test("a bitmap that arrives after the src moved on is not painted", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })
    const el = fakeCanvas("/old.jpg")
    const instance = mountHook(createHeroBackdropHook(cache), el)

    el.dataset.src = "/new.jpg"
    instance.updated()
    decoder.resolve("/old.jpg")
    await flush()

    expect(el.draws).toEqual([])
    const bitmap = decoder.resolve("/new.jpg")
    await flush()
    expect(el.draws).toEqual([{ bitmap, x: 0, y: 0 }])
  })

  test("updated repaints when a patch reset the canvas size", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })
    const loading = cache.load("/hero.jpg")
    const bitmap = decoder.resolve("/hero.jpg")
    await loading
    const el = fakeCanvas("/hero.jpg")
    const instance = mountHook(createHeroBackdropHook(cache), el)

    // morphdom syncing the server markup drops the client-set width/height.
    el.width = 300
    el.height = 150
    instance.updated()

    expect(el.draws).toEqual([{ bitmap, x: 0, y: 0 }, { bitmap, x: 0, y: 0 }])
    expect(el.width).toBe(3840)
  })

  test("a failed decode marks the slot failed and leaves nothing painted", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })
    const el = fakeCanvas("/hero.jpg")
    mountHook(createHeroBackdropHook(cache), el)

    decoder.reject("/hero.jpg")
    await flush()

    expect(el.draws).toEqual([])
    expect(el.dataset.heroState).toBe("failed")
  })
})

describe("warmHeroBackdrops", () => {
  test("decodes the given URLs one after another into the cache", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })

    const warming = warmHeroBackdrops(["/a", "/b"], cache)
    await flush()
    expect(decoder.calls).toEqual(["/a"])
    decoder.resolve("/a")
    await flush()
    expect(decoder.calls).toEqual(["/a", "/b"])
    decoder.resolve("/b")
    await warming

    expect(cache.has("/a")).toBe(true)
    expect(cache.has("/b")).toBe(true)
  })

  test("a URL that fails to decode does not stop the rest", async () => {
    const decoder = fakeDecoder()
    const cache = createBitmapCache({ capacity: 3, decode: decoder.decode })

    const warming = warmHeroBackdrops(["/a", "/b"], cache)
    await flush()
    decoder.reject("/a")
    await flush()
    decoder.resolve("/b")
    await warming

    expect(cache.has("/a")).toBe(false)
    expect(cache.has("/b")).toBe(true)
  })
})

// The resize the browser would do, recorded: a new bitmap at the asked size.
function fakeResize() {
  const calls = []
  const resize = async (bitmap, options) => {
    calls.push(options)
    return fakeBitmap(`${bitmap.name}@${options.resizeWidth}`, options.resizeWidth, options.resizeHeight)
  }
  return { resize, calls }
}

describe("fitToScreen", () => {
  test("a 4K picture on a 1080p screen is kept at the screen's size and the full one closed", async () => {
    const full = fakeBitmap("hero", 3840, 2160)
    const { resize, calls } = fakeResize()
    const fitted = await fitToScreen(full, { width: 1920, height: 1080 }, resize)
    expect([fitted.width, fitted.height]).toEqual([1920, 1080])
    expect(calls[0].resizeQuality).toBe("high")
    expect(full.closed).toBe(true)
  })

  test("a 4K picture on a 4K screen is kept as decoded", async () => {
    const full = fakeBitmap("hero", 3840, 2160)
    const { resize, calls } = fakeResize()
    expect(await fitToScreen(full, { width: 3840, height: 2160 }, resize)).toBe(full)
    expect(calls).toEqual([])
    expect(full.closed).toBe(false)
  })

  test("a picture smaller than the screen is never enlarged", async () => {
    const full = fakeBitmap("hero", 1920, 1080)
    const { resize, calls } = fakeResize()
    expect(await fitToScreen(full, { width: 3840, height: 2160 }, resize)).toBe(full)
    expect(calls).toEqual([])
  })

  test("a picture of another shape still covers the screen, as the hero's object-fit does", async () => {
    const wide = fakeBitmap("wide", 5120, 2160)
    const { resize } = fakeResize()
    const fitted = await fitToScreen(wide, { width: 1920, height: 1080 }, resize)
    expect([fitted.width, fitted.height]).toEqual([2560, 1080])
  })
})

describe("displaySize", () => {
  test("is the screen in device pixels: CSS pixels times the device pixel ratio", () => {
    expect(displaySize({ width: 960, height: 540 }, { width: 960, height: 540 }, 2)).toEqual({ width: 1920, height: 1080 })
  })

  test("a viewport larger than the reported screen wins: headless Chromium reports a small screen", () => {
    expect(displaySize({ width: 800, height: 600 }, { width: 1920, height: 1080 }, 1)).toEqual({ width: 1920, height: 1080 })
  })
})
