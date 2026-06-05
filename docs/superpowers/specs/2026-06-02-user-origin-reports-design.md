# M4 — User-origin Reports + Discovery Badge — Design

> Phase 4, Milestone 4 of the observability dashboard campaign
> (`campaigns/observability-dashboard.md`). The final Phase 4 milestone.

## Problem

Auto-detection (Phases 1–3) catches breakage the system can *see*. Two gaps remain:

1. **Undetected breakage.** A media lover notices something is off, but no `:log`
   or `:subsystem` incident fired. They have no way to hand the developer a
   consented report with cross-subsystem context.
2. **Discovery.** A user who isn't on `/status` has no signal that the system
   detected a problem worth looking at.

M4 closes both. Reporting is always composed **from the status page** — never
about specific media titles. Two reporting cases share one consent modal:

- **Identified incident** (already shipped, M2): the drill-in's per-incident
  "Report this" anchors the report to a detected `Bucket`.
- **Generic report** (new): "something's wrong and the system didn't flag it" —
  no bucket; instead a current-state snapshot is attached so the developer still
  gets context.

## Non-goals (YAGNI)

- No per-entity / per-media-title reporting.
- The consent modal stays on `/status` (not globally mounted).
- No new in-app surface for *viewing* user reports — they land in GitHub via the
  report transport; locally they are persisted only for the record / correlation.

## Architecture

Three independent units, each testable in isolation:

1. **`Store.create_user_incident/1`** — the durable `:user`-incident write path.
2. **Generic-report orchestration + entry point** — board-header "Report a
   problem" → snapshot → consent modal → persist + submit.
3. **Discovery badge** — `Settings.diagnostics_seen_at` + a count + a sidebar
   badge that clears on `/status` visit.

The consent modal is **generalized** to be source-agnostic as part of unit 2.

---

### Unit 1 — `Store.create_user_incident/1`

The `Incident` schema already supports this fully — `@origins [:log, :subsystem,
:user]`, plus `user_description`, `scope`, `first_context` fields. **No
migration.**

```elixir
@spec create_user_incident(map()) :: {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
def create_user_incident(attrs)
```

Behavior, distinct from `upsert_log_incident`/`raise_subsystem_fault`:

- **No grouping / no dedup.** Each user report is its own incident. `fingerprint`
  is unique per report (e.g. `"user-" <> Ecto.UUID.generate()`), so the partial
  unique index on `fingerprint` never collides and no read-then-write is needed —
  this writer is independent of the single-serial-writer invariant on the `:log`
  path.
- Fields set: `origin: :user`, `status: :open`, `severity: :warning` (user
  reports are not auto-detected faults; lowest severity), `count: 1`,
  `first_seen == last_seen == now`, `user_description`, `first_context`
  (the snapshot), `message`/`display_title` (a fixed human label, e.g.
  `"User report"`), `app_version_at_first` (current version, same source the
  other create paths use).
- `scope` is reserved (`nil` for v1 — generic reports have no scope; the field
  stays for a future per-area refinement).

Exposed from `MediaCentaur.ErrorReports` via `defdelegate`.

---

### Unit 2 — Generic-report flow + consent-modal generalization

**Entry point.** A `<.button variant="outline">Report a problem</.button>` in the
board header (next to the health summary). `phx-click="open_generic_report"`.

**Modal generalization (the clean seam).** Today `ReportModal.update/2` matches
`%{bucket: bucket}` and calls `ReportPayload.build(bucket, EnvMetadata.collect())`
itself — coupling the modal to `Bucket`. Refactor so **StatusLive builds the
payload** and passes it in:

- `ReportModal` accepts `payload` (a `%ReportPayload{}` with `title` + `body`)
  instead of `bucket`. It seeds `title`/`body` from the payload and is otherwise
  unchanged (3-step narrative → review → consent → submit; `submit_payload/2`;
  copy-fallback).
- StatusLive owns payload construction for **both** cases:
  - Identified incident (`open_error_report_modal`): `ReportPayload.build(bucket,
    EnvMetadata.collect())` — moved out of the modal, same result.
  - Generic (`open_generic_report`): build a current-state snapshot, then a
    payload from it (see below).

This is a net architectural improvement — the modal becomes "edit + consent +
submit this payload," source-agnostic, and `ReportPayload` gains a generic
builder beside its bucket builder.

**Current-state snapshot.** On `open_generic_report`, StatusLive calls
`ContextSnapshot.assemble(:user, %{})` (no triggering ids) → redacted recent
log lead-up + registry vitals + contributor context + env metadata. Built **at
open** (reflects state when the user noticed the problem), carried in the modal
assigns, persisted **at submit**.

**Payload from snapshot.** A new `ReportPayload.build_generic/1` (or
`build_from_context/2`) renders the snapshot into a `title`
(e.g. `"[user] Generic report"`) + `body` (the snapshot, plain-language sections
+ a technical block — same rendering style M2 uses for an incident's
`first_context`). The user's free-text narrative (step 1) is the primary content
and is prepended via the existing `assemble_body/2`.

**Submit.** Orchestration lives in the context (not the LiveView) — a thin
`ErrorReports.create_user_report/2` keeps the cross-context persist+submit out of
StatusLive. On send+consent the modal calls it:
1. `create_user_incident/1` with `user_description: narrative`, `first_context:
   snapshot`.
2. `submit_payload/2` with the assembled body (narrative + snapshot body).
3. Returns `{:ok, url}` / `{:fallback, text}` to the modal's existing result view.

(The snapshot + assembled body are carried in the modal assigns from open; the
modal passes them to `create_user_report/2`.)

Abandoned compose sessions (no consent) persist nothing.

---

### Unit 3 — Discovery badge

**Persistence.** A `Settings` entry keyed `"diagnostics_seen_at"` holding an ISO
timestamp. Read via `Settings.get_by_key/1`; write via the existing upsert path.
**When absent (never visited), the count treats it as the epoch** — every open
detected incident is "unseen" — so a first-run user sees the badge immediately.

**Count.** `Store.count_unseen_incidents(since)` (delegated as
`ErrorReports.count_unseen_incidents/1`) — the web layer passes `since` so the
context gains no `Settings` dependency:

- counts incidents where `status != :resolved` AND `origin in [:log, :subsystem]`
  AND `first_seen > since`.
- **Excludes `:user`** (self-created — the user already knows) and resolved.
- One indexed count.

**Render.** The sidebar `/status` nav item (`layouts.ex`) shows the count as a
small badge. The badge is a single **`variant="error"`** attention dot —
intentionally NOT severity-graded: it carries only a count (no max-severity), and
a discovery dot collapsing to one attention color reads more clearly than a
two-tone nav indicator. Color is still reserved for signal, **hidden when 0**. No
Console look / chip palette ([[feedback-no-console-look-or-chip-palette]]). The
count is assigned as `:diagnostics_unseen` (threaded to `Layouts.app` like
`current_path`).

**Clearing + liveness.**
- Visiting `/status` advances `diagnostics_seen_at` to `now` (in StatusLive
  `handle_params`/mount-after-connect) → next count is 0 → badge clears.
- The badge is in the app shell (every page), so it updates **app-wide** via a
  shared `on_mount` hook that (a) assigns `unseen_incident_count` at mount and
  (b) `attach_hook(:handle_info, ...)` on the `Topics.error_reports()` broadcast
  to recompute the assign — no per-LiveView `handle_info` boilerplate. The hook
  lives in `MediaCentaurWeb` (e.g. `on_mount {MediaCentaurWeb.DiagnosticsBadge,
  :default}`) and is attached in the router's `live_session`.

---

## Data flow (generic report)

```
board "Report a problem"
  → StatusLive: ContextSnapshot.assemble(:user, %{})  [snapshot built]
  → ReportPayload.build_generic(snapshot)             [title+body]
  → ReportModal(payload:)                             [3-step consent]
     step1 narrative (primary)  → step2 review/edit exact text → step3 consent
  → send+consent:
       Store.create_user_incident(user_description: narrative, first_context: snapshot)
       ErrorReports.submit_payload(assembled, ...)    [{:ok,url} | {:fallback,text}]
  → result view (sent / copy-fallback)
```

Discovery badge is orthogonal: any open `:log`/`:subsystem` incident newer than
`diagnostics_seen_at` increments the sidebar badge until the user opens `/status`.

## Error handling

- Snapshot assembly never raises into the request — `ContextSnapshot.assemble`
  already returns a map; if a contributor errors it degrades (existing behavior).
- `create_user_incident` returning `{:error, changeset}` surfaces as a fallback
  result (the report still offers copy-to-clipboard); we do not block submit on
  the local persist failing — submission to the developer is the priority.
- Transport failure → existing `{:fallback, text}` copy path (M2).
- Missing/unset `diagnostics_seen_at` → count treats all as unseen (safe default).

## Testing

Reproducible, no network (transport injected), generic placeholders only.

1. **Store.create_user_incident** — persists `origin: :user`, no grouping (two
   calls = two incidents), `first_context`/`user_description` stored,
   `severity: :warning`, `status: :open`.
2. **unseen_incident_count / count_unseen_incidents** — excludes `:user`,
   excludes `:resolved`, respects `first_seen > since`; epoch/nil default counts
   all detected.
3. **Generic report orchestration** — snapshot built, incident persisted,
   `submit_payload` called via injected transport; abandoned (no consent)
   persists nothing.
4. **Modal generalization** — `ReportModal` renders + submits a `payload` from
   both a bucket-derived and a snapshot-derived source (LiveView test); the
   bucket entry path still works end-to-end.
5. **Badge** — sidebar shows count from `unseen_incident_count`, hidden at 0;
   visiting `/status` advances `diagnostics_seen_at` and clears it; the
   `on_mount` hook live-refreshes on an `error_reports` broadcast.
6. **Stories (MC0009)** — the discovery badge component; the generic-mode consent
   modal step 1 (primary narrative) if it diverges visibly from the incident
   variation.

## Files (anticipated)

- `lib/media_centaur/error_reports/store.ex` — `create_user_incident/1`,
  `count_unseen_incidents/1`.
- `lib/media_centaur/error_reports.ex` — delegates + `create_user_report/2`
  (context-owned orchestration), `unseen_incident_count/0`.
- `lib/media_centaur/error_reports/report_payload.ex` — `build_generic/1`.
- `lib/media_centaur_web/live/status_live.ex` — `open_generic_report`, payload
  construction for both paths, `diagnostics_seen_at` advance.
- `lib/media_centaur_web/live/status_live/report_modal.ex` — `payload:` instead
  of `bucket:`.
- `lib/media_centaur_web/diagnostics_badge.ex` — `on_mount` hook.
- `lib/media_centaur_web/components/layouts.ex` — badge on the `/status` nav.
- `lib/media_centaur_web/router.ex` — attach the hook in the `live_session`.
- Stories + tests per the Testing section.

## Decisions

- **No migration** — the `Incident` schema already carries `:user` origin +
  `user_description`/`scope`/`first_context`.
- **User reports don't group** — each is its own incident; independent of the
  `:log` single-writer invariant.
- **Badge excludes `:user`** — discovery is about breakage the user *hasn't*
  seen; self-filed reports don't qualify.
- **Modal generalized to accept a payload** — decouples it from `Bucket`; both
  reporting cases share it.
