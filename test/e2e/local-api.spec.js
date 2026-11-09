/**
 * The Local API's use cases, end to end against the showcase instance
 * (`campaigns/local-api.md`, M10). Prowlarr, the download clients and TMDB
 * are stand-ins: every release search answers the same public-domain film's
 * releases, so a plan for any other title finds nothing, and no grab leaves
 * the machine.
 *
 * The fixtures are the showcase's own titles: film 10331, which the library
 * has, and series 990001, which it does not. The spec turns the feature on
 * and generates a key through Settings, as a person would. Requests go
 * through Node's fetch, not Playwright's request context, whose failure log
 * prints every header, the key included. It discards and cancels what it
 * starts, so it can run again against the same instance.
 */
import { test, expect } from "@playwright/test"

const OWNED_FILM = 10331
const SERIES = 990001

let base
let key

async function connected(page) {
  await page.waitForSelector("[data-phx-main].phx-connected")
}

async function generateKey(page) {
  await page.goto("/settings?section=features")
  await connected(page)
  const toggle = page.locator("[phx-value-feature=local_api]")
  if ((await toggle.getAttribute("aria-checked")) !== "true") await toggle.click()
  await expect(toggle).toHaveAttribute("aria-checked", "true")

  await page.goto("/settings?section=local-api")
  await connected(page)
  if (await page.locator("#generate-api-key").count()) {
    await page.locator("#generate-api-key").click()
  } else {
    await page.locator("#replace-api-key").click()
    await page.locator("#replace-api-key").click()
  }
  return (await page.locator("#local-api-key").textContent()).trim()
}

async function call(method, path, data, { authorized = true } = {}) {
  const headers = { "Content-Type": "application/json" }
  if (authorized) headers.Authorization = `Bearer ${key}`

  const response = await fetch(`${base}/api/v1${path}`, {
    method,
    headers,
    body: data === undefined ? undefined : JSON.stringify(data),
    signal: AbortSignal.timeout(30_000),
  })
  const text = await response.text()
  return { status: response.status, body: text ? JSON.parse(text) : null }
}

async function waitForPlan(id) {
  let plan
  await expect
    .poll(
      async () => {
        plan = (await call("GET", `/plans/${id}`)).body
        return plan.status === "committed" || plan.status === "discarded" || plan.awaiting_approval
      },
      { timeout: 30_000 }
    )
    .toBe(true)
  return plan
}

async function discardOpenPlans(mediaType, tmdbId) {
  const { body } = await call("GET", `/titles/${mediaType}/${tmdbId}`)
  for (const id of body.plan_ids) await call("POST", `/plans/${id}/discard`)
}

test.describe("local api", () => {
  test.beforeAll(async ({ browser, baseURL }) => {
    base = baseURL
    const page = await browser.newPage()
    key = await generateKey(page)
    await page.close()

    await discardOpenPlans("tv", SERIES)
  })

  test("UC10: status, the spec, and a request without the key", async () => {
    const status = await call("GET", "/status")
    expect(status.status).toBe(200)
    expect(status.body.capabilities.acquisition).toBe(true)

    const spec = await call("GET", "/openapi.json")
    expect(spec.body.openapi).toBe("3.1.0")

    expect((await call("GET", "/status", undefined, { authorized: false })).status).toBe(401)
  })

  test("UC1, UC7, UC8: an owned film, an automatic series plan, a repeat, the title's state", async () => {
    const owned = await call("POST", "/plans", { tmdb_id: OWNED_FILM, media_type: "movie", approval_policy: "automatic" })
    expect(owned.status).toBe(422)
    expect(owned.body.error.code).toBe("nothing_to_plan")

    const request = { tmdb_id: SERIES, media_type: "tv", approval_policy: "automatic", scope: "everything" }
    const created = await call("POST", "/plans", request)
    expect(created.status).toBe(202)

    const repeat = await call("POST", "/plans", request)
    expect(repeat.status).toBe(409)
    expect(repeat.body.error.code).toBe("already_downloading")

    const state = await call("GET", `/titles/tv/${SERIES}`)
    expect(state.body).toMatchObject({ in_library: false, plan_ids: [created.body.id] })

    // Nothing the stand-in answers is this series, so the plan stops for a person.
    const plan = await waitForPlan(created.body.id)
    expect(plan).toMatchObject({ status: "ready", awaiting_approval: true })
    expect(new Set(plan.units.map((unit) => unit.gap))).toEqual(new Set(["not_found"]))

    expect((await call("POST", `/plans/${plan.id}/discard`)).body.status).toBe("discarded")
  })

  test("UC2, UC3: a series plan for chosen episodes, reviewed by a person", async () => {
    const created = await call("POST", "/plans", { tmdb_id: SERIES, media_type: "tv", episodes: [{ season: 1, episode: 1 }] })
    expect(created.status).toBe(202)
    expect(created.body.units.map((unit) => [unit.season_number, unit.episode_number])).toEqual([[1, 1]])

    const plan = await waitForPlan(created.body.id)
    expect(plan).toMatchObject({ status: "ready", approval_policy: "review", awaiting_approval: true })

    const approve = await call("POST", `/plans/${plan.id}/approve`)
    expect(approve.body.error.code).toBe("nothing_to_grab")
    expect((await call("POST", `/plans/${plan.id}/discard`)).status).toBe(200)
  })

  test("UC4, UC5, UC6: pick a release, follow it, choose another, cancel", async () => {
    const query = "Night of the Living Dead 1968"
    const search = await call("GET", `/releases?q=${encodeURIComponent(query)}`)
    expect(search.status).toBe(200)
    const [term] = search.body.terms
    expect(term.status).toBe("ok")
    const [first, second] = term.releases

    const grab = await call("POST", "/grabs", { query, releases: [{ guid: first.guid, term: term.term }] })
    expect(grab.status).toBe(202)
    const id = grab.body.pursuit_id

    const detail = await call("GET", `/pursuits/${id}`)
    expect(detail.body).toMatchObject({ id, state: "active", units_wanted: 1, units_satisfied: 0 })
    expect(detail.body.available_actions).toContain("cancel")

    const alternatives = await call("GET", `/pursuits/${id}/alternatives`)
    expect(alternatives.status).toBe(200)
    const other = alternatives.body.releases.find((release) => release.guid !== first.guid) ?? second

    const chosen = await call("POST", `/pursuits/${id}/alternatives`, { guid: other.guid })
    expect(chosen.status).toBe(200)

    expect((await call("POST", `/pursuits/${id}/cancel`)).body.state).toBe("cancelled")
    expect((await call("GET", `/pursuits/${id}`)).body.state).toBe("cancelled")
  })

  test("UC9: auto-grab on and off for a series", async () => {
    const on = await call("PUT", `/titles/tv/${SERIES}/auto-grab`)
    expect(on.status).toBe(200)
    expect(on.body.auto_grab).toBe(true)

    const off = await call("DELETE", `/titles/tv/${SERIES}/auto-grab`)
    expect(off.body.auto_grab).toBe(false)
  })
})
