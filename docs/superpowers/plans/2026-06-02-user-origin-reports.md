# M4 — User-origin Reports + Discovery Badge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let a user file a generic "something's wrong" report from the status page (carrying a current-state context snapshot) and surface a discovery badge on the Status nav for unseen auto-detected incidents.

**Architecture:** A new `:user`-incident write path on the durable `Store` (no migration — the schema already supports `origin: :user`); the M2 consent modal generalized to submit a pre-built `payload` from either a `Bucket` or a snapshot; and a discovery badge driven by a `diagnostics_seen_at` Settings timestamp + an app-wide `on_mount` hook. The web layer owns the `diagnostics_seen_at` persistence so `ErrorReports` gains no dependency on `Settings`.

**Tech Stack:** Elixir, Phoenix LiveView (LiveComponent + `on_mount`/`attach_hook`), Ecto/SQLite, ExUnit.

**Spec:** `docs/superpowers/specs/2026-06-02-user-origin-reports-design.md`

**Repo rules:** commit straight to `main` (no branch); never add a `Co-Authored-By: Claude` trailer; zero compile warnings; generic placeholders only (no real titles); reproducible tests (transport injected, no network); do NOT run `mix ecto.migrate`/seeds (prod DB).

---

## File Structure

- `lib/media_centaur/error_reports/incident.ex` — add `user_changeset/1` (insert changeset forcing `origin: :user`).
- `lib/media_centaur/error_reports/store.ex` — add `create_user_incident/1` (no-grouping insert) and `count_unseen_incidents/1` (badge query).
- `lib/media_centaur/error_reports/report_payload.ex` — add `build_generic/2` (snapshot + env → `%{title, body, labels}`).
- `lib/media_centaur/error_reports.ex` — delegates: `create_user_incident/1`, `count_unseen_incidents/1`; plus orchestration `build_generic_report/0` and `create_user_report/2`.
- `lib/media_centaur_web/diagnostics_badge.ex` — NEW web module: `on_mount` hook, `seen_at/0`, `mark_seen/0`, `count/0` (owns the `diagnostics_seen_at` Settings entry).
- `lib/media_centaur_web/live/status_live/report_modal.ex` — accept `payload` (+ optional `snapshot`) instead of `bucket`; `send` branches incident vs generic.
- `lib/media_centaur_web/live/status_live.ex` — build payload for the bucket path; `open_generic_report` event + button; advance `diagnostics_seen_at` on visit.
- `lib/media_centaur_web/components/layouts.ex` — render the badge on the `/status` nav item.
- `lib/media_centaur_web/router.ex` — attach the `DiagnosticsBadge` hook in the `live_session`.
- Stories + tests as noted per task.

---

## Task 1: `Store.create_user_incident/1` (the `:user` write path)

**Files:**
- Modify: `lib/media_centaur/error_reports/incident.ex` (add `user_changeset/1`)
- Modify: `lib/media_centaur/error_reports/store.ex` (add `create_user_incident/1`)
- Test: `test/media_centaur/error_reports/store_test.exs`

- [ ] **Step 1: Write the failing test.** Append to `store_test.exs`:

```elixir
describe "create_user_incident/1" do
  test "persists an open :user incident with description and frozen context" do
    {:ok, incident} =
      Store.create_user_incident(%{
        user_description: "Something looks off on the home page",
        first_context: %{"vitals" => %{"tmdb" => %{"ok" => true}}}
      })

    assert incident.origin == :user
    assert incident.status == :open
    assert incident.severity == :warning
    assert incident.count == 1
    assert incident.user_description == "Something looks off on the home page"
    assert incident.first_context == %{"vitals" => %{"tmdb" => %{"ok" => true}}}
    assert incident.fingerprint =~ "user-"
  end

  test "does not group — two reports create two incidents" do
    {:ok, a} = Store.create_user_incident(%{user_description: "one", first_context: %{}})
    {:ok, b} = Store.create_user_incident(%{user_description: "two", first_context: %{}})
    refute a.id == b.id
    assert a.fingerprint != b.fingerprint
  end
end
```

- [ ] **Step 2: Run it — expect FAIL** (`create_user_incident/1` undefined):
`mix test test/media_centaur/error_reports/store_test.exs`

- [ ] **Step 3: Add `user_changeset/1` to `incident.ex`** (after `subsystem_changeset/1`, before `recurrence_changeset/2`):

```elixir
@doc """
Insert changeset for a user-filed (`:user`) report. Forces `origin: :user`.
Ungrouped — each report is its own incident with a unique `fingerprint`.
"""
@spec user_changeset(map()) :: Ecto.Changeset.t()
def user_changeset(attrs) do
  %__MODULE__{}
  |> cast(attrs, [
    :message,
    :display_title,
    :fingerprint,
    :severity,
    :status,
    :count,
    :first_seen,
    :last_seen,
    :user_description,
    :first_context,
    :scope,
    :app_version_at_first
  ])
  |> put_change(:origin, :user)
  |> validate_required([:fingerprint, :severity, :first_seen, :last_seen])
  |> unique_constraint(:fingerprint, name: :incidents_fingerprint_index)
end
```

- [ ] **Step 4: Add `create_user_incident/1` to `store.ex`** (near the other create paths; read `open_log_incident/1` for the `app_version`/`now` helpers it uses and reuse them):

```elixir
@doc """
Creates an ungrouped open `:user` incident from a user-filed report. Unlike the
`:log`/`:subsystem` paths there is no dedup — every report is its own incident
(unique `fingerprint`), so this writer is independent of the single-serial-writer
invariant on `upsert_log_incident/1`.
"""
@spec create_user_incident(map()) :: {:ok, Incident.t()} | {:error, Ecto.Changeset.t()}
def create_user_incident(attrs) do
  now = DateTime.utc_now()

  %{
    fingerprint: "user-" <> Ecto.UUID.generate(),
    severity: :warning,
    status: :open,
    count: 1,
    first_seen: now,
    last_seen: now,
    display_title: "User report",
    message: "User-filed report",
    app_version_at_first: app_version()
  }
  |> Map.merge(attrs)
  |> Incident.user_changeset()
  |> Repo.insert()
end
```
(Confirm the existing private helper that yields the current version — read `open_log_incident/1`. If it is named differently than `app_version/0`, call that name instead. If there is none, use `Application.spec(:media_centaur, :vsn) |> to_string()`.)

- [ ] **Step 5: Run tests — expect PASS.** `mix test test/media_centaur/error_reports/store_test.exs`

- [ ] **Step 6: Commit.**
```bash
git add lib/media_centaur/error_reports/incident.ex lib/media_centaur/error_reports/store.ex test/media_centaur/error_reports/store_test.exs
git commit -m "feat(error-reports): Store.create_user_incident — ungrouped :user write path"
```

---

## Task 2: badge count — `Store.count_unseen_incidents/1` + delegate

**Files:**
- Modify: `lib/media_centaur/error_reports/store.ex`
- Modify: `lib/media_centaur/error_reports.ex`
- Test: `test/media_centaur/error_reports/store_test.exs`

- [ ] **Step 1: Write the failing test.** Append to `store_test.exs`:

```elixir
describe "count_unseen_incidents/1" do
  test "counts open detected incidents newer than `since`, excluding :user and resolved" do
    old = ~U[2020-01-01 00:00:00Z]
    since = ~U[2026-01-01 00:00:00Z]
    newer = ~U[2026-06-01 00:00:00Z]

    # detected + open + newer than since → counts
    {:ok, _} = Store.upsert_log_incident(log_attrs(fingerprint: "fp-new", first_seen: newer, last_seen: newer))
    # detected but older than since → excluded
    {:ok, _} = Store.upsert_log_incident(log_attrs(fingerprint: "fp-old", first_seen: old, last_seen: old))
    # user-origin → excluded even though newer
    {:ok, _} = Store.create_user_incident(%{user_description: "x", first_context: %{}})

    assert Store.count_unseen_incidents(since) == 1
  end

  test "epoch `since` counts all open detected incidents" do
    {:ok, _} = Store.upsert_log_incident(log_attrs(fingerprint: "fp-a"))
    assert Store.count_unseen_incidents(~U[1970-01-01 00:00:00Z]) >= 1
  end
end
```
Reuse the file's existing `:log` attrs helper if present; otherwise add a local `defp log_attrs(overrides)` building a valid map for `upsert_log_incident/1` (read an existing test in this file for the required keys: `component`, `fingerprint`, `severity`, `message`/`display_title`, `first_seen`, `last_seen`). Default `first_seen`/`last_seen` to `DateTime.utc_now()`.

- [ ] **Step 2: Run it — expect FAIL.** `mix test test/media_centaur/error_reports/store_test.exs`

- [ ] **Step 3: Add the query to `store.ex`:**

```elixir
@doc """
Counts open (non-resolved) auto-detected (`:log`/`:subsystem`) incidents first
seen after `since`. Powers the discovery badge — `:user` reports are excluded
(self-filed, so the user has already "seen" them).
"""
@spec count_unseen_incidents(DateTime.t()) :: non_neg_integer()
def count_unseen_incidents(%DateTime{} = since) do
  Incident
  |> where([i], i.status != :resolved)
  |> where([i], i.origin in [:log, :subsystem])
  |> where([i], i.first_seen > ^since)
  |> select([i], count(i.id))
  |> Repo.one()
end
```

- [ ] **Step 4: Delegate from `error_reports.ex`** (beside the other `defdelegate`s):

```elixir
defdelegate create_user_incident(attrs), to: Store
defdelegate count_unseen_incidents(since), to: Store
```

- [ ] **Step 5: Run tests — expect PASS.** `mix test test/media_centaur/error_reports/store_test.exs`

- [ ] **Step 6: Commit.**
```bash
git add lib/media_centaur/error_reports/store.ex lib/media_centaur/error_reports.ex test/media_centaur/error_reports/store_test.exs
git commit -m "feat(error-reports): count_unseen_incidents for the discovery badge"
```

---

## Task 3: `ReportPayload.build_generic/2` + orchestration

**Files:**
- Modify: `lib/media_centaur/error_reports/report_payload.ex`
- Modify: `lib/media_centaur/error_reports.ex`
- Test: `test/media_centaur/error_reports/report_payload_test.exs` (create if absent) + `test/media_centaur/error_reports/report_submission_test.exs`

- [ ] **Step 1: Write the failing test** for `build_generic/2` (in `report_payload_test.exs`):

```elixir
defmodule MediaCentaur.ErrorReports.ReportPayloadTest do
  use ExUnit.Case, async: true
  alias MediaCentaur.ErrorReports.ReportPayload

  test "build_generic/2 renders a title + body from a snapshot and env" do
    snapshot = %{
      "lead_up" => [%{"ts" => "2026-06-01T00:00:00Z", "level" => "error",
                      "component" => "tmdb", "message" => "boom", "correlated" => false}],
      "vitals" => %{"tmdb" => %{"ok" => true}},
      "contributor" => %{},
      "triggering_ids" => %{},
      "crash_reason" => nil
    }
    env = %{app_version: "1.2.3", os: "linux", elixir: "1.19"}

    %{title: title, body: body, labels: labels} = ReportPayload.build_generic(snapshot, env)

    assert title =~ "report"
    assert body =~ "Environment"
    assert body =~ "boom"
    assert "incident" in labels
  end
end
```

- [ ] **Step 2: Run it — expect FAIL.** `mix test test/media_centaur/error_reports/report_payload_test.exs`

- [ ] **Step 3: Implement `build_generic/2`** in `report_payload.ex` (add the `EnvMetadata` render + a small snapshot renderer; `EnvMetadata.render/1` already exists and is used by `IssueUrl`):

```elixir
@spec build_generic(map(), EnvMetadata.t()) :: ReportTransport.payload()
def build_generic(snapshot, %{} = env) when is_map(snapshot) do
  %{
    title: "User report — something looks wrong",
    body: generic_body(snapshot, env),
    labels: @labels
  }
end

defp generic_body(snapshot, env) do
  IO.iodata_to_binary([
    "## Environment\n",
    EnvMetadata.render(env),
    "\n\n## Recent log context (normalized)\n\n",
    format_lead_up(Map.get(snapshot, "lead_up", [])),
    "\n\n## System vitals\n\n```json\n",
    Jason.encode!(Map.get(snapshot, "vitals", %{}), pretty: true),
    "\n```\n",
    "\n---\nReported via Media Centaur's in-app error reporter (generic report).\n"
  ])
end

defp format_lead_up([]), do: "(no log context captured)\n"

defp format_lead_up(lines) do
  Enum.map_join(lines, "\n", fn line ->
    "    #{line["ts"]} #{line["level"]} [#{line["component"]}] #{line["message"]}"
  end)
end
```
(`@labels` is the module's existing `["incident", "auto-reported"]`. Confirm `Jason` is the JSON lib in use — grep `Jason.encode` in `lib/`; if the repo uses `JSON`/another, match it.)

- [ ] **Step 4: Run the payload test — expect PASS.**

- [ ] **Step 5: Write the orchestration test** (in `report_submission_test.exs`, which already injects a transport):

```elixir
describe "create_user_report/2" do
  test "persists a :user incident and submits the payload" do
    snapshot = %{"vitals" => %{}, "lead_up" => []}
    payload = %{title: "T", body: "edited body", labels: ["incident"]}

    assert {:ok, "https://github.com/owner/reports/issues/42"} =
             ErrorReports.create_user_report(
               %{user_description: "broke", snapshot: snapshot, payload: payload},
               transport: OkTransport
             )

    [incident] = ErrorReports.list_incidents(status: :open) |> Enum.filter(&(&1.origin == :user))
    assert incident.user_description == "broke"
    assert incident.first_context == snapshot
  end
end
```
(Match the `OkTransport`/URL fixture already used by the existing `submit_payload/2` tests in this file — reuse that stub, don't invent a new one.)

- [ ] **Step 6: Implement `build_generic_report/0` + `create_user_report/2`** in `error_reports.ex`:

```elixir
alias MediaCentaur.ErrorReports.{ContextSnapshot, EnvMetadata, ReportPayload}

@doc """
Assembles a generic (un-anchored) user report: a current-state context snapshot
plus the `%{title, body, labels}` payload to seed the consent modal. The caller
keeps `snapshot` to persist on submit via `create_user_report/2`.
"""
@spec build_generic_report() :: %{snapshot: map(), payload: ReportPayload.payload()}
def build_generic_report do
  snapshot = ContextSnapshot.assemble(:user, %{})
  %{snapshot: snapshot, payload: ReportPayload.build_generic(snapshot, EnvMetadata.collect())}
end

@doc """
Persists the `:user` incident (best-effort — submission is not blocked if the
local write fails) and submits the (already edited + assembled) payload.
"""
@spec create_user_report(map(), keyword()) :: {:ok, String.t()} | {:fallback, String.t()}
def create_user_report(%{user_description: desc, snapshot: snapshot, payload: payload}, opts \\ []) do
  _ = create_user_incident(%{user_description: desc, first_context: snapshot})
  submit_payload(payload, opts)
end
```
(Confirm `ContextSnapshot.assemble/3`, `EnvMetadata.collect/0`, `submit_payload/2`, and the `ReportPayload.payload()` type alias names by reading those modules; adjust the alias list if any already exists in the file.)

- [ ] **Step 7: Run both tests — expect PASS.**
`mix test test/media_centaur/error_reports/report_payload_test.exs test/media_centaur/error_reports/report_submission_test.exs`

- [ ] **Step 8: Commit.**
```bash
git add lib/media_centaur/error_reports/report_payload.ex lib/media_centaur/error_reports.ex test/media_centaur/error_reports/report_payload_test.exs test/media_centaur/error_reports/report_submission_test.exs
git commit -m "feat(error-reports): generic report payload + create_user_report orchestration"
```

---

## Task 4: generalize the consent modal to accept a `payload`

Pure refactor — the bucket path must stay green; no generic behavior yet.

**Files:**
- Modify: `lib/media_centaur_web/live/status_live/report_modal.ex`
- Modify: `lib/media_centaur_web/live/status_live.ex`
- Test: `test/media_centaur_web/live/status_live/` (the existing report-modal / status_live tests)

- [ ] **Step 1: Read** `report_modal.ex` and `status_live.ex`'s `open_error_report_modal`/render to see the current `bucket={@report_bucket}` wiring (the modal currently calls `ReportPayload.build(bucket, EnvMetadata.collect())` in its own `update/2`).

- [ ] **Step 2: Change `ReportModal.update/2`** to accept a pre-built payload instead of a bucket:

```elixir
@impl true
def update(%{payload: payload} = assigns, socket) do
  {:ok,
   socket
   |> assign(assigns)
   |> assign_new(:step, fn -> 1 end)
   |> assign_new(:narrative, fn -> "" end)
   |> assign_new(:title, fn -> payload.title end)
   |> assign_new(:body, fn -> payload.body end)
   |> assign_new(:consent, fn -> false end)
   |> assign_new(:snapshot, fn -> Map.get(assigns, :snapshot) end)
   |> assign_new(:report_result, fn -> nil end)}
end
```
Remove the `ReportPayload.build(...)`/`EnvMetadata.collect()` call and the now-unused aliases from the modal. Keep `@labels`.

- [ ] **Step 3: In `status_live.ex` `open_error_report_modal`,** build the payload before assigning, and pass `payload` (not `bucket`) to the component. In the bucket lookup handler:

```elixir
def handle_event("open_error_report_modal", params, socket) do
  bucket = resolve_report_bucket(socket, params["fingerprint"])

  payload =
    bucket && MediaCentaur.ErrorReports.ReportPayload.build(bucket, MediaCentaur.ErrorReports.EnvMetadata.collect())

  {:noreply,
   assign(socket,
     show_report_modal: not is_nil(payload),
     report_payload: payload,
     report_snapshot: nil
   )}
end
```
Rename the `report_bucket` assign to `report_payload` (+ add `report_snapshot`); update `mount` defaults and `report_cancel` accordingly. Update the `<.live_component module={ReportModal} .../>` invocation:

```elixir
<.live_component
  :if={@show_report_modal}
  id="error-report-modal"
  module={ReportModal}
  payload={@report_payload}
  snapshot={@report_snapshot}
/>
```
(Keep `resolve_report_bucket/2` — the existing fingerprint→bucket lookup. If it's currently inline, leave it.)

- [ ] **Step 4: `send` handler in the modal stays the same for the incident path** — it already calls `ErrorReports.submit_payload/2` with the assembled body. No change needed yet (generic branch comes in Task 5).

- [ ] **Step 5: Run the status/report tests — expect PASS** (the bucket reporting path still works end-to-end):
`mix test test/media_centaur_web/live/status_live/ test/media_centaur_web/live/status_live_test.exs`

- [ ] **Step 6: Commit.**
```bash
git add lib/media_centaur_web/live/status_live/report_modal.ex lib/media_centaur_web/live/status_live.ex
git commit -m "refactor(status): consent modal accepts a pre-built payload (decouple from Bucket)"
```

---

## Task 5: generic report entry point + flow

**Files:**
- Modify: `lib/media_centaur_web/live/status_live.ex`
- Modify: `lib/media_centaur_web/live/status_live/report_modal.ex`
- Test: `test/media_centaur_web/live/status_live/` (new generic-report assertions)

- [ ] **Step 1: Write the failing LiveView test** (in the status_live report test file):

```elixir
test "generic 'Report a problem' opens the modal and submits a user report", %{conn: conn} do
  {:ok, view, _html} = live_async!(conn, "/status")

  view |> element("[data-testid=report-a-problem]") |> render_click()
  assert has_element?(view, "[data-testid=report-modal]")

  # The modal is a LiveComponent — its events carry phx-target={@myself}, so drive
  # them by CLICKING the modal's elements (NOT bare render_click(view, "next")).
  view |> element("#error-report-modal form") |> render_change(%{"value" => "home page is blank"})
  view |> element("#error-report-modal button", "Next") |> render_click()
  view |> element("#error-report-modal button", "Next") |> render_click()
  view |> element("#error-report-modal [phx-click='toggle_consent']") |> render_click()
  view |> element("#error-report-modal button", "Send to the developer") |> render_click()
  html = render(view)

  assert html =~ "Report sent" or html =~ "Copy this report"
  assert Enum.any?(MediaCentaur.ErrorReports.list_incidents(), &(&1.origin == :user))
end
```
The live modal calls `submit_payload`/`create_user_report` WITHOUT injected opts, so with no token configured in test it returns `{:fallback, _}` (copy path) — deterministic, no network. Assert on `"Copy this report"` + the persisted `:user` incident. Confirm the exact button labels/selectors against the current `report_modal.ex` render (it uses "Next" / "Send to the developer" and a `toggle_consent` control) and adjust the selectors to match.

- [ ] **Step 2: Run it — expect FAIL** (`[data-testid=report-a-problem]` missing).

- [ ] **Step 3: Add the entry button** to the board header in `status_live.ex` render (near the health summary):

```heex
<.button variant="outline" size="sm" data-testid="report-a-problem" phx-click="open_generic_report">
  Report a problem
</.button>
```

- [ ] **Step 4: Add the `open_generic_report` handler** in `status_live.ex`:

```elixir
def handle_event("open_generic_report", _params, socket) do
  %{snapshot: snapshot, payload: payload} = MediaCentaur.ErrorReports.build_generic_report()

  {:noreply,
   assign(socket, show_report_modal: true, report_payload: payload, report_snapshot: snapshot)}
end
```

- [ ] **Step 5: Branch the modal's `send`** in `report_modal.ex` — generic when a snapshot is present, incident otherwise:

```elixir
def handle_event("send", _p, %{assigns: %{consent: false}} = socket), do: {:noreply, socket}

def handle_event("send", _p, socket) do
  assembled = %{
    title: socket.assigns.title,
    body: ErrorReports.assemble_body(socket.assigns.narrative, socket.assigns.body),
    labels: @labels
  }

  result =
    case socket.assigns.snapshot do
      nil ->
        ErrorReports.submit_payload(assembled)

      snapshot ->
        ErrorReports.create_user_report(%{
          user_description: socket.assigns.narrative,
          snapshot: snapshot,
          payload: assembled
        })
    end

  {:noreply, assign(socket, :report_result, result)}
end
```

- [ ] **Step 6: (Optional) generic-mode copy** — if step 1's prompt should differ for generic ("Describe what's wrong" vs the incident framing), pass a `mode`/label through. Keep minimal: the existing narrative step works for both. Only add a label tweak if it reads wrong in the running app.

- [ ] **Step 7: Run tests — expect PASS.** `mix test test/media_centaur_web/live/status_live/`

- [ ] **Step 8: Commit.**
```bash
git add lib/media_centaur_web/live/status_live.ex lib/media_centaur_web/live/status_live/report_modal.ex test/media_centaur_web/live/status_live/
git commit -m "feat(status): generic 'Report a problem' entry → snapshot → user report"
```

---

## Task 6: discovery badge (Settings seen_at + on_mount hook + nav badge)

**Files:**
- Create: `lib/media_centaur_web/diagnostics_badge.ex`
- Modify: `lib/media_centaur_web/live/status_live.ex` (advance seen_at on visit)
- Modify: `lib/media_centaur_web/components/layouts.ex` (render badge)
- Modify: `lib/media_centaur_web/router.ex` (attach hook)
- Test: `test/media_centaur_web/diagnostics_badge_test.exs` + a layout/nav assertion
- Story: `storybook/status/` (badge) if it's a standalone component

- [ ] **Step 1: Write the failing test** for the badge module:

```elixir
defmodule MediaCentaurWeb.DiagnosticsBadgeTest do
  use MediaCentaur.DataCase, async: false
  alias MediaCentaurWeb.DiagnosticsBadge
  alias MediaCentaur.ErrorReports.Store

  test "count/0 reflects unseen detected incidents and mark_seen/0 clears it" do
    {:ok, _} = Store.upsert_log_incident(%{
      component: :tmdb, fingerprint: "fp-badge", severity: :error,
      message: "x", display_title: "[TMDB] x",
      first_seen: DateTime.utc_now(), last_seen: DateTime.utc_now()
    })

    assert DiagnosticsBadge.count() >= 1
    DiagnosticsBadge.mark_seen()
    assert DiagnosticsBadge.count() == 0
  end
end
```
(Match the exact `upsert_log_incident/1` attrs the Store requires — copy from a passing Store test.)

- [ ] **Step 2: Run it — expect FAIL.**

- [ ] **Step 3: Implement `diagnostics_badge.ex`:**

```elixir
defmodule MediaCentaurWeb.DiagnosticsBadge do
  @moduledoc """
  Discovery badge for the Status nav: the count of unseen, auto-detected open
  incidents (`:log`/`:subsystem` newer than `diagnostics_seen_at`). Owns the
  `diagnostics_seen_at` Settings entry so `ErrorReports` needs no `Settings` dep.

  Provides an `on_mount` hook that assigns `:diagnostics_unseen` app-wide and
  live-refreshes it on the `error_reports` PubSub broadcast.
  """
  import Phoenix.LiveView, only: [attach_hook: 4]
  import Phoenix.Component, only: [assign: 3]

  alias MediaCentaur.{ErrorReports, Settings}
  alias MediaCentaur.Settings.Entry
  alias MediaCentaur.Topics

  @key "diagnostics_seen_at"
  @epoch ~U[1970-01-01 00:00:00Z]

  @spec count() :: non_neg_integer()
  def count, do: ErrorReports.count_unseen_incidents(seen_at())

  @spec seen_at() :: DateTime.t()
  def seen_at do
    case Settings.get_by_key(@key) do
      {:ok, %Entry{value: %{"at" => iso}}} ->
        case DateTime.from_iso8601(iso) do
          {:ok, dt, _} -> dt
          _ -> @epoch
        end

      _ ->
        @epoch
    end
  end

  @spec mark_seen() :: :ok
  def mark_seen do
    Settings.find_or_create_entry(%{key: @key, value: %{"at" => DateTime.to_iso8601(DateTime.utc_now())}})
    :ok
  end

  @doc "on_mount hook: assigns :diagnostics_unseen and live-refreshes on broadcast."
  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket), do: Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.error_reports())

    socket =
      socket
      |> assign(:diagnostics_unseen, count())
      |> attach_hook(:diagnostics_badge, :handle_info, &refresh/2)

    {:cont, socket}
  end

  defp refresh({:buckets_changed, _}, socket), do: {:cont, assign(socket, :diagnostics_unseen, count())}
  defp refresh(_msg, socket), do: {:cont, socket}
end
```
(Confirm the `error_reports` broadcast message shape — the topic carries `{:buckets_changed, buckets}` per `status_live.ex`. If there is also an incident-level broadcast, match whichever fires on incident open. Confirm `Settings.find_or_create_entry/1` accepts a `value` map — it does per `settings.ex`.)

- [ ] **Step 4: Run the badge test — expect PASS.**

- [ ] **Step 5: Attach the hook** in `router.ex` — add `on_mount {MediaCentaurWeb.DiagnosticsBadge, :default}` to the authenticated `live_session` that hosts the app pages (read the router to find the right `live_session` block; add alongside any existing `on_mount`).

- [ ] **Step 6: Advance seen_at on `/status` visit** — in `status_live.ex`, after the socket is connected (in `handle_params` or a connected-mount branch), call `MediaCentaurWeb.DiagnosticsBadge.mark_seen()` and re-assign `diagnostics_unseen: 0`. Guard with `connected?(socket)` so the dead render doesn't write.

- [ ] **Step 7: Render the badge** in `layouts.ex` on the `/status` nav item — show `@diagnostics_unseen` when `> 0`:

```heex
<.badge :if={(@diagnostics_unseen || 0) > 0} variant="error" size="xs" class="ml-auto">
  {@diagnostics_unseen}
</.badge>
```
Place it inside the `/status` `sidebar-link`. The assign comes from the on_mount hook; default to `0` where the layout might render without it (use `assigns[:diagnostics_unseen]`). Use color only for severity (error/warning) per the design system.

- [ ] **Step 8: Add a nav assertion** — extend a layout or page test asserting the badge shows the count when an unseen detected incident exists and is hidden at 0. (If a standalone badge component is extracted, add a Storybook story per MC0009; if it's just a `<.badge>` inline in the nav, no new story is needed — `badge/1` already has one.)

- [ ] **Step 9: Run tests — expect PASS.** `mix test test/media_centaur_web/diagnostics_badge_test.exs test/media_centaur_web/live/status_live/`

- [ ] **Step 10: Commit.**
```bash
git add lib/media_centaur_web/diagnostics_badge.ex lib/media_centaur_web/router.ex lib/media_centaur_web/live/status_live.ex lib/media_centaur_web/components/layouts.ex test/media_centaur_web/diagnostics_badge_test.exs
git commit -m "feat(status): discovery badge on the Status nav (diagnostics_seen_at)"
```

---

## Task 7: full gate + campaign reconcile + wiki

- [ ] **Step 1: `mix precommit`** — exit 0 (format, Credo incl. MC0008/MC0009, boundaries, sobelow, deps.audit, full Elixir + JS). Boundary check is the key risk: confirm `ErrorReports` did NOT gain a `Settings` dep (the seen_at read/write lives in `MediaCentaurWeb.DiagnosticsBadge`). The known `store_test`/acquisition parallelism flakes are unrelated — if one appears, confirm it passes in isolation. Fix anything genuinely caused by this change.

- [ ] **Step 2: Reconcile the campaign** — in `campaigns/observability-dashboard.md`, mark M4 done (user-origin generic reports + Store `:user` path + discovery badge), and note Phase 4 / the campaign complete. Bump `last_updated` if needed.

- [ ] **Step 3: Wiki** — user-visible change: add a short "Report a problem" entry to the appropriate *Using Media Centaur* / Troubleshooting wiki page (`~/src/media-centaur/media-centaur.wiki/`), describing the status-page generic report + the discovery badge. Commit + push the wiki (separate repo).

- [ ] **Step 4: Commit.**
```bash
git add campaigns/observability-dashboard.md
git commit -m "docs(campaign): M4 (user-origin reports + discovery badge) shipped"
```

---

## Notes for the implementer

- **No migration** — the `Incident` schema already has `origin: :user`, `user_description`, `scope`, `first_context`.
- **Boundary discipline** — `ErrorReports` must not depend on `Settings`. The `diagnostics_seen_at` persistence lives entirely in `MediaCentaurWeb.DiagnosticsBadge`; the context only exposes `count_unseen_incidents(since)`.
- **Best-effort persist** — `create_user_report/2` submits even if the local `:user` incident write fails (submission to the developer is the priority).
- **Reproducible tests** — inject the transport (`opts[:transport]`); the live generic flow with no token configured yields `{:fallback, _}` (copy path) in test — assert on that + the persisted incident, never on network.
- **Design system** — board button is `<.button variant="outline">`; the badge uses `<.badge>` with a severity variant, hidden at 0; color only for health/severity; no Console look / chip palette.
- **Modal contract** — `snapshot` present ⇒ generic (persist + submit); `snapshot` nil ⇒ incident (submit only). Both submit the user-edited `title`/`body` via `assemble_body/2`.
