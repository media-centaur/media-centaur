# Observability Dashboard — Design Spec

**Date:** 2026-05-31
**Status:** approved design, pre-implementation
**Campaign:** [`campaigns/observability-dashboard.md`](../../../campaigns/observability-dashboard.md)

## Motivation

Media Centaur now has end users who aren't the author. They hit bugs, tell the
author informally, and the author can't reproduce because he has no access to
their machine, their library, or their logs. We need the user to be able to
(a) *notice* something is wrong, (b) *see* which subsystem is failing, and
(c) *hand the author an incident report carrying enough cross-subsystem context
to actually diagnose it* — without the author ever touching their machine, and
in language a non-engineer understands.

## What already exists (evolution, not greenfield)

A substantial slice is built and must be reused:

- **`MediaCentaur.ErrorReports`** context (`deps: [Console]`):
  - `Buckets` — GenServer that subscribes to the Console PubSub stream,
    fingerprint-**groups** `:error` entries into `%Bucket{}` (count, first/last
    seen, 5 redacted samples), serving a **1-hour rolling, in-memory** snapshot.
  - `Fingerprint` — stable `{component, normalized_message}` hashing.
  - `Redactor` — two-pass redaction (config-secret strip + regex for
    paths/UUIDs/IPs/emails/digits). **Reuse + extend.**
  - `EnvMetadata` — version, OTP/Elixir, OS, locale, uptime. **Reuse.**
  - `IssueUrl` — builds a **public**-repo GitHub `new/issue` URL opened via
    `window.open` (≤7.5 KB budget). **Replaced** (see D2).
- **`/status`** (`StatusLive`) — operational hub with an `error_summary_card`,
  a `pipeline_card` (per-stage status dots / throughput / failures), a
  `directories` card (drive + at-risk health), `external_integrations`,
  playback, library stats. Long scrolling page, not a subsystem-health board.
- **`StatusLive.ReportModal`** — bucket radio list + redacted preview + confirm.
- **Subsystem taxonomy** = Console component atoms (`Console.View`):
  `:watcher :pipeline :tmdb :playback :library :acquisition :system`
  `:phoenix :ecto :live_view`, each with a chip color in `app.css`.

### The gaps

1. **Volatile** — buckets are in-memory, 1-hour rolling; a restart or an hour
   erases the evidence. Defeats "user reports yesterday's bug."
2. **Wrong submission path** — `window.open` → a *public* issue URL needs a
   GitHub account and posts to a public tracker.
3. **No subsystem-health surface; errors only** — `/status` shows a flat error
   list, ignores warnings, and has no per-subsystem board.
4. **Only catches logged errors** — subsystems can malfunction *without* logging
   an `:error`, and users hit problems that never produce a log line at all.

## Decisions

| # | Decision |
|---|----------|
| D1 | **Primary audience: the end-user reporter — a media lover, not a programmer.** Operator/health view secondary. The entire surface must read as a polished part of a *media app*, not a developer ops console: plain language, calm visuals, no jargon, no console/log-tool aesthetic. |
| D2 | **Submission: private repo + embedded scoped token.** A separate **private** `media-centaur-reports` repo is the inbox. The app files issues via the GitHub **REST API over HTTPS**, authenticated by a **fine-grained PAT scoped to Issues:write on that one repo**. No user GitHub account, no `git`/SSH/`gh`, no infra. Token via `MediaCentaur.Config`, rotatable through the release channel. REST body (~65 KB) drops the `window.open` size ladder, so reports carry full context. |
| D3 | **Reporting is an informed-consent, plain-language, 3-step guided flow** (see "Reporting flow"). Auto-redaction + **manual user redaction** + an explicit consent gate + a clear "only the core dev team can access this" statement. Nothing leaves the machine without consent. |
| D4 | **Durable store.** Persist `warning`+`error` events and incidents so they survive restart and outlive the 1-hour window; in-memory `Buckets` becomes a cache over the store. |
| D5 | **Keep the existing fingerprint grouping**, made durable and extended to warnings. |
| D6 | **Rebuild `/status` into the subsystem-health dashboard** (absorb the error card + report flow). No second operational page. |
| D7 | **Visual direction: Subsystem Health Board** (mockup 1) as the spine; ranked grouped-issue list as the drill-in. **Do NOT reproduce the Console's look or the per-subsystem chip palette** (user dislikes both). Subsystems are identified by **name + a neutral monochrome icon + typography**; **color is reserved exclusively for health/severity** (success/warning/error) — calm/neutral when healthy. Drill-in event lists are clean sans-serif rows (monospace only for ids/paths), not console-style. |
| D8 | **Passive discovery badge** on the Status nav item — count of unacknowledged open incidents — so users notice without being told. |
| D9 | **Incidents have three origins** — `:log` (passive fingerprint capture), `:subsystem` (active self-detection), `:user` (human-reported, no error) — all flowing into one durable store and one packaging + report pipeline. |
| D10 | **Incidents are stateful conditions** with an `open → resolved` lifecycle (+ `acknowledged`), not just error tallies. Subsystem-asserted faults open when tripped and resolve when cleared. |
| D11 | **Hybrid context capture** — freeze a lean snapshot at incident time on **first AND latest** occurrence (throttled), and enrich with **live "now"** state at report time, clearly labeled "at incident" vs "now." |
| D12 | **Per-subsystem incident-context contributors** — each subsystem owns an `IncidentContext` module (detect + contribute), wired via a **runtime registry** so `Diagnostics` calls contributors without a compile-time dependency (boundary-clean IoC). Baseline packaging is the floor; contributors are enrichment, phased in. |
| D13 | **Lead-up isolation: time-window + id correlation** — the ±window cross-subsystem slice, with lines sharing the triggering id (file/entity/tmdb/infohash) highlighted as the causal chain. A threaded pipeline correlation id is a deferred enhancement. |

### Open / deferred

- **Context naming.** ~~Broadens from "error reports" to "subsystem health +
  incident reporting." Keep `ErrorReports` or rename (`Diagnostics`/
  `Observability`).~~ **Resolved 2026-05-31: keep `MediaCentaur.ErrorReports`**
  (no rename). Revisit only if the moduledoc names two responsibilities with
  "and" (modularity rule). Note: this doc still uses "Diagnostics" loosely as a
  role name in places; the actual context module is `ErrorReports`.
- **Acknowledgement model** for the discovery badge — persist a
  `diagnostics_seen_at` in `Settings`; badge counts open incidents newer than
  it; visiting `/status` advances it. Finalize in the dashboard phase.
- **Threaded correlation id** through the Broadway pipeline (D13) — deferred
  enhancement once the baseline proves too noisy.

## Incident model

An **incident** is a durable, stateful record; an **incident report** is what we
package from it and send.

### Origins (D9)

- **`:log`** — a `warning`/`error` log event is fingerprinted and grouped
  (existing `Buckets`/`Fingerprint`, made durable).
- **`:subsystem`** — a subsystem detects it is malfunctioning (a condition, not
  necessarily a logged error) and raises an incident with a frozen snapshot.
- **`:user`** — a user reports a problem that produced no log error; we attach
  current context + their description + scope.

### Record shape (durable)

`incidents` table, keyed for grouping where applicable:

- `id`, `origin` (`:log | :subsystem | :user`), `kind` (subsystem-defined
  symbol for asserted faults, e.g. `:drive_offline`, `:pipeline_stalled`),
  `component`, `fingerprint` (nullable for `:user`), `severity`,
  `status` (`open | acknowledged | resolved`), `count`,
  `first_seen`, `last_seen`, `resolved_at`,
  `first_context` (JSON), `latest_context` (JSON, throttled refresh),
  `user_description` (text, `:user` only), `scope` (global / subsystem /
  `{entity_type, entity_id}`), `app_version_at_first`.

`diagnostic_events` table is the raw `warning`/`error` event log feeding `:log`
incidents (one row per event; redacted at capture; scalar-pruned `metadata`,
`module`, `occurred_at`, `fingerprint`). Bounded by a periodic prune
(~30 days or a row cap). The in-memory `Buckets` cache is rebuilt from these
durable tables on boot.

### Context snapshot (D11)

A **frozen** snapshot is captured at incident time (first + latest occurrence,
throttled). It is assembled by a dedicated process — **never in the logger
handler**, which only hands off — and contains:

1. **Lead-up logs** — pulled from the **volatile Console buffer** at that instant
   (the only place the full cross-subsystem firehose exists), last ~50 lines /
   ±30s, every line run through the `Redactor` (widened redaction surface), with
   lines sharing the triggering id **highlighted** (D13).
2. **Subsystem vitals** — gathered **asynchronously**, calling every subsystem's
   status function (`Pipeline.Stats`, `TMDB.RateLimiter.status`,
   `Watcher.Supervisor.statuses`, DB ping…), each wrapped in `try/rescue/catch`
   so a dead subsystem records `"unavailable"` rather than crashing capture.
   All subsystems, not just the firing one (cross-subsystem causality).
3. **Crash reason / stacktrace** (`:crash_reason` metadata) when present.
4. **Triggering ids** — tmdb/entity/file/infohash from metadata (ids kept;
   titles/paths redacted).
5. **Per-subsystem contributor block** — see D12.

A **live "now"** enrichment is added at report time: current vitals, current
recurrence (count, first/last, version-at-first vs now), `EnvMetadata` — all
labeled distinctly from the frozen "at incident" data.

## Per-subsystem integration (D12)

Each subsystem owns a small module implementing a `Diagnostics.IncidentContext`
behaviour with two halves:

- **Detect** — `assess() :: :ok | {:fault, kind, severity, ids}` (called by a
  lightweight periodic **evaluator** in Diagnostics for duration/trend
  conditions), plus the subsystem may **raise/resolve** acute faults directly
  via the Diagnostics API the instant they happen.
- **Contribute** — `gather(triggering_ids) :: map` returning the structured
  context that subsystem deems relevant for its own incidents.

Boundary-clean via a **runtime registry** mapping `component → module`
(config-driven), so `Diagnostics` invokes contributors/assessors **without a
compile-time dep** on any subsystem — subsystems depend on `Diagnostics` to
implement the behaviour, not the reverse (inversion of control).

Example contributions, given the triggering ids:

- **Import (pipeline)** — file's stage journey (parse result, search candidates,
  chosen tmdb id, ingest outcome), queue depth.
- **Metadata (tmdb)** — last request params, response status, rate-limiter
  window, retry state.
- **Downloads (acquisition)** — release/grab details, infohash, indexer,
  download-client queue + connectivity.
- **Library Scanning (watcher)** — dir/mount/drive availability, the fs event,
  at-risk state.

A subsystem with no contributor still produces the full **baseline** report.
Contributors roll out incrementally — pipeline, tmdb, acquisition first.

## Reporting flow (informed consent, D3)

A **guided 3-step** modal, plain language, no jargon. The report that reaches
GitHub is structured/technical; what the user sees is a **plain-language
rendering** of that same data with a "view technical details" expander.

1. **What happens** — a short friendly explanation + four promises:
   *you'll see everything first · you can remove anything · only the core dev
   team can see it · nothing sends without your OK.*
2. **Review & remove** — the payload as plain-language sections
   (*App version & system · The error details · Recent activity (logs) · Your
   settings summary*), each removable, log lines individually removable.
   Auto-redaction is already applied and noted ("we already hid your file names
   and titles"); this adds a **manual** layer of control.
3. **Consent & send** — restate the access statement (private inbox, core dev
   team only, not a public page) and require an explicit affirmation
   ("I've reviewed this and agree to send it to the development team") before
   the Send button is active.

Submission posts to the private repo (D2). On no-token (dev/showcase) or network
failure, fall back to presenting the redacted bundle text to copy — never lose
the report. No separate "download bundle" UI.

## Architecture seams

- **Capture** stays cheap/crash-free in the logger handler (hand off only); a
  dedicated durable sink/incidents process does persistence, async vitals
  gathering, and snapshot freezing. Volatile (Console) and durable (Diagnostics)
  paths remain independent — a failure in one must not take down the other.
  - *Phase 1 realization (2026-05-31):* the durable path is an **independent
    `:logger` handler** (`ErrorReports.LogHandler`), a peer of `Console.Handler`
    rather than a subscriber to its PubSub — so a crashed/backed-up Console
    buffer cannot starve durable capture. The handler only builds an entry (via
    the shared `Console.Entry.from_log_event/3`) and casts to `Buckets`, which
    persists under a **per-fingerprint write throttle** (`PersistThrottle`) so an
    error storm cannot flood the single SQLite writer. Pending coalesced writes
    flush periodically and on graceful `terminate/2`.
- **Submission**: a `ReportTransport` behaviour with a GitHub-REST private-repo
  implementation; tests stub it (no network). `IssueUrl`'s public-URL role is
  replaced; `Redactor` + `EnvMetadata` reused. `error_report.js` (`window.open`)
  is removed; the LiveView performs the POST and pushes success/failure back.
- **Dashboard**: rebuild `StatusLive` render into the Subsystem Health Board
  (tiles → drill-in: ranked issues + that subsystem's diagnostics), warnings in
  health, the discovery badge, the 3-step consent modal. Reuse `<.button>`,
  `<.badge>`, glass surfaces, and the always-in-DOM modal — but **not** the
  Console aesthetic or chip palette (D7): subsystems by name + neutral icon +
  type, color reserved for health/severity. A Storybook story per new
  component (MC0009).

## Phasing

1. **Phase 1 — Durable incident store.** `diagnostic_events` + `incidents`
   tables + migration; `:log` capture of warning+error; fingerprint grouping
   made durable; `Buckets` rebuilt from store on boot; retention prune;
   `health/0` rollup. **End:** errors survive restart and outlive 1h.
2. **Phase 2 — Incident detection + contributors.** `IncidentContext` behaviour
   + runtime registry; the periodic evaluator + raise/resolve API + the
   `open → resolved` lifecycle; frozen context snapshots (first+latest) with
   lead-up + vitals + ids + correlation; first-class contributors for pipeline,
   tmdb, acquisition. **End:** subsystems self-report faults with rich context.
3. **Phase 3 — Submission swap.** `ReportTransport` + GitHub-REST private-repo;
   token config + rotation; remove JS hook; offline/no-token fallback. **End:**
   one consented submission files a private issue, no GitHub account.
4. **Phase 4 — Dashboard + consent reporting flow.** Rebuild `/status` as the
   Subsystem Health Board (warnings, drill-in, discovery badge); the guided
   3-step informed-consent modal with manual redaction; the human-reported
   (`:user`) entry points (global + contextual per-entity). **End:** the page
   and the report experience the campaign set out to build.

Ordering: 1 is the backbone. 2 deepens capture. 3 swaps outbound. 4 is the
user-facing surface (could partially overlap 3 against the old submission).

## Testing

Test-first throughout; no network in tests.

- Capture: level filtering (warning+error), persistence, retention-prune
  boundary, `Buckets` rebuild-from-store on boot.
- Incident lifecycle: open→resolve transitions; subsystem-asserted raise/resolve;
  periodic evaluator tripping/clearing a duration condition; throttled
  latest-context refresh.
- Context snapshot: lead-up slice + redaction over every line; async vitals with
  a dead subsystem yielding `"unavailable"`; id-correlation highlighting.
- Contributor registry: component→module resolution; baseline when no
  contributor; a sample contributor's `gather/1` shape.
- `Redactor` — keep/extend explicit cases (paths/titles/keys); trust-critical.
- `ReportTransport` stubbed; assert payload shape; never call GitHub.
- Consent flow: manual section/line removal actually drops payload content;
  Send disabled until consent; offline/no-token fallback path.
- `StatusLive` smoke test (board + drill-in); a Storybook story per new
  component (MC0009).

## Privacy

Documented in the context moduledoc + wiki: exactly what is captured, what the
`Redactor` strips, that events/incidents are stored **locally only**, that the
user can manually remove anything, that only the core dev team can access a
submitted report, and that **nothing leaves the machine without explicit
consent**.

## Pointers

- Mockups: `mockups/observability/{1-subsystem-health-board,2-incident-triage-feed,3-operations-cockpit}/`
- Existing context: `lib/media_centaur/error_reports/`
- Existing page: `lib/media_centaur_web/live/status_live.ex`, `status_live/report_modal.ex`
- Taxonomy + chips: `lib/media_centaur/console/view.ex`, `assets/css/app.css` (chip palette)
- Conventions: ADR-042 (campaigns), ADR-029 (data decoupling / Boundary), UI skill / UIDRs
