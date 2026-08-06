/**
 * Structural coverage of `config.js` against the templates that depend on it.
 *
 * The input system is configuration-driven: a page can declare a behavior,
 * zones and nav items in its template and still be completely dead, because
 * nothing links the template's strings to `config.js`. `buildNavGraph` returns
 * `{}` for an unknown layout key and the arrow keys silently do nothing —
 * there is no error, no warning, and every unit test still passes.
 *
 * That is exactly how `/reconcile` shipped: a full set of nav attributes, a
 * registered page behavior, and no `reconcile` entry in this config at all.
 *
 * So these tests do not enumerate pages by hand — a hand-written list is what
 * failed. They read the templates, extract every declaration the input system
 * consumes, and assert the config answers it. A new page that forgets its
 * config wiring fails here, without anyone remembering to add it.
 */

import { describe, expect, test } from "bun:test"
import { readdirSync, readFileSync } from "fs"
import { join } from "path"
import { inputConfig } from "../config"

const WEB_DIR = join(import.meta.dir, "..", "..", "..", "..", "lib", "media_centaur_web")

/** Every `.ex`/`.heex` file under lib/media_centaur_web, recursively. */
function templateFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) return templateFiles(path)
    return /\.(ex|heex)$/.test(entry.name) ? [path] : []
  })
}

const TEMPLATES = templateFiles(WEB_DIR).map((path) => ({
  path,
  source: readFileSync(path, "utf8"),
}))

/** Collect every literal value of `attribute="…"` across the templates. */
function declared(attribute) {
  const pattern = new RegExp(`${attribute}="([^"]+)"`, "g")
  const found = new Map()

  for (const { path, source } of TEMPLATES) {
    for (const [, value] of source.matchAll(pattern)) {
      if (!found.has(value)) found.set(value, path)
    }
  }

  return found
}

/**
 * The DOM zone names the config can actually resolve, read out of the
 * selectors themselves rather than from the config keys — `zone_tabs` is
 * keyed with an underscore but matches `data-nav-zone='zone-tabs'`, and
 * deriving it from the selector keeps that mapping in one place.
 */
const RESOLVABLE_ZONES = new Set(
  Object.values(inputConfig.contextSelectors)
    .map((selector) => selector.match(/data-nav-zone='([^']+)'/)?.[1])
    .filter(Boolean),
)

describe("config.js covers what the templates declare", () => {
  test("every data-nav-default-zone names a layout key", () => {
    const missing = [...declared("data-nav-default-zone")]
      .filter(([zone]) => !inputConfig.layouts[zone])
      .map(([zone, path]) => `${zone} (${path})`)

    expect(missing).toEqual([])
  })

  test("every data-nav-default-zone has a cursor start priority", () => {
    const missing = [...declared("data-nav-default-zone")]
      .filter(([zone]) => !inputConfig.cursorStartPriority[zone])
      .map(([zone, path]) => `${zone} (${path})`)

    expect(missing).toEqual([])
  })

  test("every data-page-behavior resolves to a behavior", () => {
    const missing = [...declared("data-page-behavior")]
      .filter(([name]) => inputConfig.createBehavior(name) === null)
      .map(([name, path]) => `${name} (${path})`)

    expect(missing).toEqual([])
  })

  test("every data-nav-zone has a context selector", () => {
    const missing = [...declared("data-nav-zone")]
      .filter(([zone]) => !RESOLVABLE_ZONES.has(zone))
      .map(([zone, path]) => `${zone} (${path})`)

    expect(missing).toEqual([])
  })
})

describe("config.js is internally consistent", () => {
  test("every context named in a layout has a selector", () => {
    const selectorKeys = new Set(Object.keys(inputConfig.contextSelectors))
    const missing = []

    for (const [zone, layout] of Object.entries(inputConfig.layouts)) {
      for (const context of Object.keys(layout)) {
        if (!selectorKeys.has(context)) missing.push(`${zone}.${context}`)
      }
    }

    expect(missing).toEqual([])
  })

  test("every layout edge points at a context the same layout defines", () => {
    const dangling = []

    for (const [zone, layout] of Object.entries(inputConfig.layouts)) {
      for (const [context, edges] of Object.entries(layout)) {
        for (const [direction, candidates] of Object.entries(edges)) {
          for (const candidate of candidates) {
            // `drawer` and `modal` are overlays — they are reachable from a
            // layout without being a zone of it.
            if (candidate === "drawer" || candidate === "modal") continue
            if (!layout[candidate]) {
              dangling.push(`${zone}.${context}.${direction} -> ${candidate}`)
            }
          }
        }
      }
    }

    expect(dangling).toEqual([])
  })

  test("every cursor start priority entry is a context of its layout", () => {
    const unknown = []

    for (const [zone, priority] of Object.entries(inputConfig.cursorStartPriority)) {
      const layout = inputConfig.layouts[zone] ?? {}
      for (const context of priority) {
        if (!layout[context]) unknown.push(`${zone}: ${context}`)
      }
    }

    expect(unknown).toEqual([])
  })
})
