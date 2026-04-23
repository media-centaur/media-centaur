# Status page error reporting — design spec

**Date:** 2026-04-24
**Status:** Accepted
**Scope:** Replace the Status page's unbounded `recent_errors_table` with a bucketed, privacy-aware error summary and add a one-click "Report to developer" flow that opens a pre-filled GitHub issue.

## Goals

1. Give the user a **glanceable** sense of whether the app is healthy, without a wall of per-file error rows.
2. **Group** errors by a stable fingerprint so the summary never grows unbounded and so two users hitting the same bug file issues with matching titles (GitHub surfaces duplicates automatically when titles match).
3. Provide a **review-before-send** modal with clear consent and a visible, redacted preview of the payload.
4. **Redact** obvious sensitive tokens (paths, UUIDs, API keys, configured URLs, IPs, emails) automatically, and warn the user to eyeball the rest before consenting.
5. Stay **browser-side**: submission is a `window.open` of a GitHub `/issues/new?title=&body=` URL. No server token, no backend call to GitHub.

## Non-goals

- Telemetry / automatic submission. Every report is an explicit per-click consent.
- Cross-user deduplication logic on our side. GitHub's existing "is this a duplicate?" UI does that job via title match.
- Error capture from outside the BEAM (e.g. mpv process crashes). Scope is errors that reach `:logger`.
- Persisting buckets across restarts. Error reporting is a here-and-now signal; restart wipes state.
- Removing `Pipeline.Stats.recent_errors` ring buffer. It's still referenced elsewhere and useful for `/console`; deprecation is a separate follow-up.
- Attaching files, large metadata dumps, or gists. URL-based issue filling only.

## Architecture

### New bounded context

A new context `MediaCentarr.ErrorReports` (no tables; all in-memory). Follows the project's bounded-context pattern: facade module exposes a small public API, internals are private.

```elixir
defmodule MediaCentarr.ErrorReports do
  use Boundary,
    deps: [MediaCentarr.Console, MediaCentarr.Config, MediaCentarr.Topics],
    exports: [Bucket]

  # Public facade
  def list_buckets(), do: Buckets.list_buckets()
  def get_bucket(fingerprint), do: Buckets.get_bucket(fingerprint)
  def subscribe(), do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.error_reports())
end
```

`MediaCentarr.Topics` gets a new `error_reports/0` returning `"error_reports:updates"`.

### Module layout

| Module | Kind | Responsibility |
|---|---|---|
| `MediaCentarr.ErrorReports` | Facade | Public API — `list_buckets/0`, `get_bucket/1`, `subscribe/0` |
| `MediaCentarr.ErrorReports.Bucket` | Struct | Exported bucket struct (see schema below) |
| `MediaCentarr.ErrorReports.Fingerprint` | Pure | Given `{component, raw_message}`, returns `%{key, display_title, normalized_message}` |
| `MediaCentarr.ErrorReports.Redactor` | Pure | Applies regex-based redaction + active-config strip of API keys and URLs |
| `MediaCentarr.ErrorReports.Buckets` | GenServer | Subscribes to Console, maintains `%{fingerprint => Bucket}`, prunes by window, throttled broadcasts |
| `MediaCentarr.ErrorReports.IssueUrl` | Pure | Builds `https://github.com/.../issues/new?title=&body=` URL with size-fallback truncation |
| `MediaCentarr.ErrorReports.EnvMetadata` | Pure | Collects app version, OTP/Elixir, OS, uptime for the payload |

`MediaCentarr.ErrorReports.Application`-supervised `Buckets` starts in the main supervision tree alongside other context GenServers.

### Boundary dependencies

`ErrorReports` depends on:

- `MediaCentarr.Console` — subscribes to `Console.subscribe()` (already exists for the `/console` LiveView), reads `Console.Entry` structs at `:error` level.
- `MediaCentarr.Config` — reads active TMDB API key and any configured URLs for the Redactor's strip pass.
- `MediaCentarr.Topics` — topic string constants.

`MediaCentarrWeb.StatusLive` gains a `MediaCentarr.ErrorReports` boundary dep (already depends on `Library`, `Playback`, etc.). The existing `MediaCentarrWeb.StatusHelpers.merge_recent_errors/2` function is deleted.

## Data flow

```
Log.error/2 call  ─┐
Broadway failure  ─┼─► :logger handler ─► Console.Buffer (ring, existing)
Ecto / Phoenix    ─┘                              │
                                                  │ "console:updates" PubSub
                                                  ▼
                                    ErrorReports.Buckets (GenServer)
                                    - filters :error level
                                    - Fingerprint + Redactor
                                    - updates %{fingerprint => Bucket}
                                    - prunes entries by window
                                                  │
                                                  │ "error_reports:updates"
                                                  │ (throttled, max 1/sec)
                                                  ▼
                                        StatusLive error card
                                                  │
                                                  │ user clicks "Report errors"
                                                  ▼
                                         ReportModal LiveComponent:
                                           radio-select a bucket
                                           see redacted preview
                                           confirm or cancel
                                                  │
                                                  │ push_event {:open_issue, url}
                                                  ▼
                                      JS hook: window.open(url, "_blank", "noopener")
```

The `:logger` handler is **not** modified. The Console buffer is the single ingress point; `ErrorReports.Buckets` is just another subscriber alongside the existing `ConsoleLive` / `ConsolePageLive`.

## Data model

### `ErrorReports.Bucket`

```elixir
defmodule MediaCentarr.ErrorReports.Bucket do
  @enforce_keys [:fingerprint, :component, :normalized_message, :display_title,
                 :count, :first_seen, :last_seen, :sample_entries]
  defstruct [:fingerprint, :component, :normalized_message, :display_title,
             :count, :first_seen, :last_seen, :sample_entries]

  @type t :: %__MODULE__{
    fingerprint: binary(),              # 16 hex chars of sha256({component, normalized_message})
    component: atom(),                  # :tmdb, :watcher, :pipeline, :library, ...
    normalized_message: binary(),       # post-Redactor
    display_title: binary(),            # "[TMDB] TMDB returned <N>: rate limited..."
    count: non_neg_integer(),           # occurrences inside the retention window
    first_seen: DateTime.t(),
    last_seen: DateTime.t(),
    sample_entries: [%{timestamp: DateTime.t(), message: binary()}]
    # up to 5 most recent same-bucket log entries, already redacted
  }
end
```

### Retention

- Window: 1 hour by default.
- Configurable via `Settings.Entry` key `error_reports.window_minutes` (integer minutes, 15..360 validated). Default read is `60`. A Settings UI control is deliberately **not** part of v1 — the key is readable but not writable from the UI; it's changeable via IEx or direct DB edit until the UI follows up.
- Buckets without any entry inside the window are dropped at prune time.
- Window is consulted at list time, not just prune time — so a 1-hour window shows exact counts even between prune ticks.
- Prune runs every 60s via `Process.send_after/3`.

### Memory cap

- Hard cap: 200 active buckets. On overflow, the bucket with the oldest `last_seen` is dropped.
- `sample_entries` capped at 5 per bucket.

## Fingerprinting

Given a Console entry with `level: :error, component: c, message: m`:

1. Pass `m` through `Redactor.normalize/1`.
2. Compute `fingerprint = :crypto.hash(:sha256, [Atom.to_string(c), 0, normalized]) |> Base.encode16(case: :lower) |> String.slice(0, 16)`.
3. Compute `display_title = "[#{component_label(c)}] #{normalized}"` with component labels `:tmdb -> "TMDB"`, `:library -> "Library"`, `:pipeline -> "Pipeline"`, `:watcher -> "Watcher"`, `:playback -> "Playback"`, `:phoenix -> "Phoenix"`, `:ecto -> "Ecto"`, `:live_view -> "LiveView"`, `:system -> "System"`. Fallback is `c |> Atom.to_string() |> String.capitalize()`.
4. Truncate title to 200 chars; body message to 500 chars (for display; full normalized message kept for fingerprinting).

## Redaction rules

Applied in order; first-match wins per token:

1. **Configured secrets** (active-config strip):
   - Replace literal occurrences of `MediaCentarr.Config.get(:tmdb_api_key)` with `<redacted:api_key>` (no-op if nil/empty or length < 8).
   - Replace literal occurrences of every URL gathered by a new helper `MediaCentarr.ErrorReports.Redactor.configured_urls/0`, which reads the existing `MediaCentarr.Config` for any known external-URL keys (e.g. Prowlarr base URL, download-client URLs) and returns a flat list of strings. New helper — implementation picks up each known config key explicitly; it does not scan the entire config tree.
2. **Regex substitutions** (applied after secret strip):
   - Absolute paths: `~r{(?<![A-Za-z0-9_])/(?:[^\s/"']+/){1,}[^\s/"']*}` → `<path>`
   - UUIDs: `~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i` → `<uuid>`
   - IPv4 addresses: `~r/\b(?:\d{1,3}\.){3}\d{1,3}\b/` → `<ip>`
   - Emails: `~r/\b[\w.+-]+@[\w.-]+\.\w{2,}\b/` → `<email>`
   - Long digit runs: `~r/\b\d{3,}\b/` → `<N>` (applied after the IP rule so IP octets don't get double-normalized)
3. **Post-processing:** `String.normalize(:nfc)`, then collapse runs of whitespace, then trim.

Same normalization is applied to sample-entry messages before they're stored in a bucket. The UI **never** shows a raw entry.

### User-facing sensitive-data warning

The modal carries a visible `alert alert-warning`:

> ⚠ Review the report below before submitting. It's been automatically scrubbed of paths, UUIDs, API keys, IPs, emails, and configured URLs — but please glance for anything else personal (titles of private files, usernames in error messages, etc.) before confirming. This will open a public GitHub issue.

## GitHub issue URL

Base: `https://github.com/media-centarr/media-centarr/issues/new?title=<encoded>&body=<encoded>`.

### Title format

```
[<Component>] <normalized message, truncated to 140 chars>
```

Deterministic given `{component, normalized_message}` — so two users filing the same bug produce matching titles. GitHub's duplicate-detection banner surfaces existing issues with similar titles as the user types.

### Body sections (priority-ordered)

```markdown
## Environment
App:     media-centarr 0.21.0
Erlang:  OTP 27 / Elixir 1.17
OS:      Linux 6.19.12-arch1-1 (x86_64)
Locale:  en_US.UTF-8
Uptime:  2h 14m

## Error
Fingerprint: 3f9c1a2b4e5d6f70
Component:   tmdb
Count:       12 (in the last 60 minutes)
First seen:  2026-04-24T13:48:02Z
Last seen:   2026-04-24T14:00:19Z

Normalized message:

    TMDB returned <N>: rate limited (retry after <N>s)

## Recent log context (normalized)

    14:00:19 error [tmdb] TMDB returned <N>: rate limited (retry after <N>s)
    13:59:47 error [tmdb] TMDB returned <N>: rate limited (retry after <N>s)
    ...

---
Reported via Media Centarr's in-app error reporter.
```

### URL-length fallback

Target ≤ 7,500 URL-encoded bytes (safe under the ~8,192-byte practical cap). `IssueUrl.build/2` returns `{:ok, url}` or `{:ok, url, [:truncated_log_context]}` (never errors — worst case is the essentials-only payload).

Truncation order (remove from the bottom):

1. Drop log-context entries one at a time, oldest first, until fit.
2. If still too long, drop recurrences-detail lines (keep count + first/last only).
3. The environment block and normalized message stay — they're the core signal.

The modal shows a banner when truncation was applied.

## UI changes

### Status page error card

Replaces `recent_errors_table/1` in `MediaCentarrWeb.StatusLive`. Rendered by a new helper function `error_summary_card/1` (kept as an in-file component — StatusLive is already a large file, but no new call site justifies a separate module yet).

**Populated state:**

```
┌─ Errors ─────────────────────── [Report errors] ─┐
│                                                   │
│  22 errors in the last hour                       │
│  across 6 distinct issues, 4 components           │
│                                                   │
│  · [TMDB] rate limited (retry after <N>s)  ×12   │
│      tmdb · 2m ago                                │
│  · [TMDB] connection refused               ×5    │
│      tmdb · 14m ago                               │
│  · [Watcher] permission denied on watch    ×3    │
│      watcher · 1h ago                             │
│                                                   │
└───────────────────────────────────────────────────┘
```

Shows top 3 buckets by `count` (ties broken by most recent `last_seen`).

**Empty state:**

```
┌─ Errors ─────────────────────────────────────────┐
│                                                  │
│  No errors in the last hour.                     │
│                                                  │
└──────────────────────────────────────────────────┘
```

Report button hidden when `buckets == []`.

### Report modal

New `MediaCentarrWeb.StatusLive.ReportModal` LiveComponent.

Header: `Send this error report to the Media Centarr developer?`

Body (top to bottom):

1. **Warning alert** (DaisyUI `alert alert-warning`, see text above).
2. **Bucket radio list.** Each row: fingerprint-shortened, display title, component badge, count, last-seen. Pre-selected: the bucket with the greatest `last_seen` (the most recent error — not the most frequent).
3. **Payload preview panel** (DaisyUI `bg-base-200 rounded p-4 font-mono text-xs whitespace-pre-wrap max-h-96 overflow-y-auto`). Shows the title + body exactly as they'll be URL-encoded.
4. **Truncation banner** (conditional) if the payload was trimmed.

Footer actions (in a `flex flex-col items-center gap-2`):

- Primary: `btn btn-primary` labeled `Confirm & open GitHub`.
- Cancel: a subtle `link link-hover text-sm text-base-content/60` labeled `No, don't send`.

Dismissal:

- `Esc` key — cancels.
- Click on the modal backdrop — cancels.
- Cancel link — cancels.
- Confirm button — emits `push_event("error_reports:open_issue", %{url: url})`.

### JS hook

New hook `assets/js/hooks/error_report.js`:

```js
export default {
  mounted() {
    this.handleEvent("error_reports:open_issue", ({url}) => {
      window.open(url, "_blank", "noopener");
    });
  }
};
```

Registered in `assets/js/app.js` alongside existing hooks.

## Error handling / edge cases

- **Unicode in error text**: Redactor calls `String.normalize(:nfc)` before regex. Regexes use `/u` flag.
- **Console buffer rotation mid-processing**: `Buckets` copies entry fields into its own `sample_entries` list; buffer rotation cannot orphan them.
- **Bursty errors** (e.g. pipeline crash loop): `Buckets` state updates in real time, but `"error_reports:updates"` broadcasts at most once per second (rate-limited via scheduled `:flush` message).
- **Window eviction timing**: prune runs every 60s. `list_buckets/0` also filters by window at call time so the UI is never out of date by more than the debounce.
- **API key not configured**: Redactor treats `nil` / `""` / strings shorter than 8 chars as no-ops to avoid replacing every lowercase `a` with `<redacted:api_key>`.
- **No buckets when Report clicked**: header button is hidden when `buckets == []`; modal is not reachable.
- **Browser blocks window.open**: JS hook logs a warning; user can copy the URL from the modal (fallback: payload preview already contains everything needed, user can manually open the repo).
- **`Buckets` crash**: supervised `:one_for_one`. A restart wipes state, same as a full BEAM restart — we accept this because errors are already visible in Console for deeper diagnosis.
- **LiveView disconnect during report**: modal state is ephemeral; on reconnect, user reopens the modal. The report is client-side so no in-flight request is lost.

## Testing

Follows the project's test-first policy and `automated-testing` skill conventions.

### Pure modules (`async: true`)

- **`Fingerprint`**:
  - Table tests: given `{component, raw_message}` tuples, assert fingerprint/display_title/normalized_message.
  - Grouping tests: distinct retry-after values collapse to one fingerprint; distinct error classes don't.
  - Unicode edge cases: NFC normalization stable across equivalent forms.
- **`Redactor`**:
  - One test per regex rule (path, UUID, IP, email, digit run).
  - Active-config strip: with a stub `Config` returning a known TMDB key, verify literal occurrences are replaced.
  - Edge cases: empty/nil key is no-op; very short key (< 8 chars) is no-op.
  - Order-of-operations: IPs preserved when adjacent to the digit-run rule.
- **`IssueUrl`**:
  - `build/2` with a small bucket returns a URL containing the expected title and body.
  - Very large bucket triggers log-context truncation; flag is returned.
  - Extreme bucket triggers recurrences truncation; environment block is always present.
  - URL is always valid: re-parse with `URI.parse/1`, check host and path.

### GenServer (`Buckets`) — public API only (ADR-026)

- Seed with fake Console entries via a test helper that calls `Console.Handler.dispatch/1` or equivalent (whichever is the public path). Never `:sys.replace_state`.
- Verify `list_buckets/0` reflects inserts, counts, last_seen updates.
- Time-travel the retention window with an injectable clock (`Buckets` takes `now_fn` in its config) to verify eviction without `Process.sleep`.
- Verify broadcast throttling: two rapid inserts produce at most one `{:buckets_changed, _}` message within 1 second.

### LiveView integration

- Mount `StatusLive`, broadcast `{:buckets_changed, snapshot}`, assert assigns update.
- Click Report button, modal component appears (test by presence of modal assign, not HTML).
- Confirm button triggers `push_event` with URL — test by asserting on the `push_event` record.
- Does **not** assert on HTML structure (project rule).

### No E2E coverage in v1

Report flow involves a third-party (GitHub). Functional coverage is handled by the unit + integration tests above. Manual smoke-test checklist lives in the implementation plan.

## Migration / removal

Single-step, same-PR:

1. Add `MediaCentarr.ErrorReports` context and its modules.
2. Register `Buckets` in the supervision tree.
3. Add `MediaCentarr.Topics.error_reports/0`.
4. Replace `StatusLive.recent_errors_table/1` + `merge_recent_errors/2` with the new summary card.
5. Delete the old table helper and the `recent_errors` assign from `StatusLive`.
6. Keep `Pipeline.Stats.recent_errors` ring buffer untouched.

No DB migration. No user-facing setting added (window stays at default 60 min; configurability lives in the spec but a UI control is a follow-up).

## Wiki updates

New behavior is user-visible. Wiki touches required alongside the PR:

- `Troubleshooting.md` — new section: "Reporting errors to the developer" with a one-paragraph description of the flow and what gets redacted.
- `FAQ.md` — add Q: "What gets sent to GitHub when I click 'Report errors'?" A: summary of environment metadata + the redacted error bucket; no personal paths or API keys; you can review the exact payload before confirming.

## Open questions / follow-ups (not in v1)

- Configurable retention window via a Settings UI control (spec supports it; UI is a follow-up).
- Per-bucket `[Report]` button on each row (option A from brainstorm) as an alternate UX if the header-level button feels too hidden.
- Deprecate/remove `Pipeline.Stats.recent_errors` once nothing reads from it.
- Telemetry counter for how many reports are opened (no submission tracking — just consent-open count).

---

**Rationale pointers:** grouping scheme (B), payload scope (B + log context), Report button (C), error sources (B), retention (ii), empty state (b) — all per the brainstorm dialogue that produced this spec on 2026-04-24.
