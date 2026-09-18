# Availability, step 2 (Prowlarr) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nothing spends a Prowlarr request — a plan's searches, the release tracker's re-planning, the Incoming page's 30-second roster read — while Prowlarr is known down; held work resumes within a minute of recovery, and every surface that explains the outage reads the one availability value instead of inferring it from the last roster read.

**Architecture:** Step 1 built `MediaCentaur.IntegrationAvailability` and made `Search.Prowlarr` its one writer for `:prowlarr`, kept fresh while down by `Search.ProbeJob` (60 s). This step attaches the remaining `:prowlarr` consumers to it: `Jobs.RunPlan` and `DropPlanner` hold instead of searching; `IndexerHealth.current/0` stops the Incoming page probing a server the probe job already owns; one new pure view model (`ViewModels.SearchOutage`) turns the value into the one sentence the gap banner and the board ticker both use, replacing two copies of the same inference over `IndexerHealth`; `Acquisition.Reactor` runs a drop-planner tick on recovery; and `Search.IncidentContext` reads the value, which retires its 900-second staleness rule so a long outage stays visible on Status. Spec: `docs/superpowers/specs/2026-09-17-availability-design.md`. Campaign: `campaigns/recurring-traffic-audit.md`.

**Tech Stack:** Elixir/Phoenix, Oban 2.24 (Lite engine; `testing: :inline` in tests), Req + `Req.Test` stubs (`:prowlarr`), Boundary, ExUnit with `MediaCentaur.DataCase` / `MediaCentaur.Case`.

---

## Rules that apply to every task

- **Never run `mix` directly.** Every mix invocation is `~/scripts/agents/agent-mix <task>` (`~/scripts/agents/agent-mix test path`, `~/scripts/agents/agent-mix format`, …). A bare `mix` takes the running dev server down.
- **One editing agent at a time in this checkout.** Reviews are read-only and may run in parallel; two concurrent editors crashed the dev server and raced on git on 2026-09-17.
- **Test-first.** Write the test, run it red for the right reason, implement, run green.
- **Sandbox rules.** Any test that calls `IntegrationAvailability.report/3` writes `:persistent_term` and must be sync: `use MediaCentaur.Case, async: false` or `use MediaCentaur.DataCase` (already sync). The sandbox restores app-owned `:persistent_term` keys at check-in, so tests never clean up availability themselves. Pure tests stay `async: true`.
- **Setting a down integration in a test** is `IntegrationAvailability.report(:prowlarr, {:down, :unreachable})` — the store directly, not `ProwlarrAvailability`, so no probe job is enqueued into the inline Oban.
- **Oban runs inline in tests.** `Oban.insert/1` executes the job in the calling process. A test that drives a *down transition* through `ProwlarrAvailability` runs the probe immediately against the `:prowlarr` stub, which must then answer `GET /api/v1/indexer`, `GET /api/v1/indexerstatus`, `GET /api/v1/downloadclient` and `POST /api/v1/downloadclient/testall`.
- **A new module plus a new `exports:` entry needs `~/scripts/agents/agent-mix compile --force` once** — Boundary's export manifest is stale otherwise and the dependent file fails to compile for a reason that is not in your diff (memory `reference-boundary-stale-export-manifest`).
- **Placeholders only** in tests and docs: "Sample Show", "Sample Movie" — never a real title.
- **Zero warnings.** `--warnings-as-errors` is on.
- The shell is fish: quote glob-like arguments (`~/scripts/agents/agent-mix test 'test/media_centaur/search/*_test.exs'`).
- Commit after each task with the trailer line `Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF`. Never add a Co-Authored-By line.

## File map

| File | Responsibility |
|---|---|
| Modify `lib/media_centaur/search/indexer_health.ex` | `current/1`: a fresh roster read while Prowlarr is up, the probe's last observation while it is down |
| Create `lib/media_centaur/acquisition/view_models/search_outage.ex` | The one sentence for a down Prowlarr, read from the availability value |
| Modify `lib/media_centaur/acquisition.ex` | Export `ViewModels.SearchOutage` |
| Modify `lib/media_centaur/acquisition/view_models/gap_verdict.ex` | Takes the sentence; stops inferring it from `IndexerHealth` |
| Modify `lib/media_centaur_web/live/incoming_live/plan_logic.ex` | The board ticker takes the same sentence |
| Modify `lib/media_centaur_web/live/incoming_live.ex` | Reads through `IndexerHealth.current/1`, holds the sentence in one assign, re-reads on a Prowlarr availability change |
| Modify `lib/media_centaur/integration_availability.ex` | `subscribe/0` |
| Modify `lib/media_centaur_web.ex` | Boundary dep on `MediaCentaur.IntegrationAvailability` |
| Modify `lib/media_centaur/acquisition/jobs/run_plan.ex` | Holds before a plan's searches |
| Modify `lib/media_centaur/acquisition/drop_planner.ex` | The tick is gated on availability, not configuration alone |
| Modify `lib/media_centaur/acquisition/reactor.ex`, `reactor/handlers.ex` | Prowlarr's recovery runs a planner tick |
| Modify `lib/media_centaur/search/incident_context.ex` | Reads the availability value; the staleness rule goes; a rejected key is its own condition |
| Modify `lib/media_centaur/acquisition/corpus.ex` | Comment: the zero-result roster read also writes availability |
| Wiki `../media-centaur.wiki/Troubleshooting.md` | What the app does while Prowlarr is down, and when it resumes |
| `campaigns/recurring-traffic-audit.md` | Status, decisions, next steps after step 2 |

---

### Task 1: `IndexerHealth.current/1` — don't probe what the probe job owns

The Incoming page reads the indexer roster every 30 seconds per open page. While Prowlarr is down that read learns nothing `Search.ProbeJob` has not already recorded a minute ago, and each failure mints a diagnostic event (measured 2026-09-17: three in 90 seconds during a 401 window). `current/1` is the read a renderer should use.

**Files:**
- Modify: `lib/media_centaur/search/indexer_health.ex`
- Test: `test/media_centaur/search/indexer_health_test.exs`

- [ ] **Step 1: Write the failing test**

Append this `describe` block after the existing `describe "check/1"` block in `test/media_centaur/search/indexer_health_test.exs`:

```elixir
  describe "current/1" do
    setup do
      client =
        Req.new(plug: {Req.Test, :prowlarr_health}, retry: false, base_url: "http://prowlarr.test")

      {:ok, client: client}
    end

    test "reads the roster while Prowlarr is up", %{client: client} do
      Req.Test.stub(:prowlarr_health, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" -> Req.Test.json(conn, [%{"id" => 1, "name" => "Indexer A", "enable" => true}])
          "/api/v1/indexerstatus" -> Req.Test.json(conn, [])
        end
      end)

      health = IndexerHealth.current(client)

      assert health.state == :ok
      assert IndexerHealth.cached() == health
    end

    test "returns the probe's last observation while Prowlarr is down, asking nobody", %{
      client: client
    } do
      IndexerHealth.cache_put(%IndexerHealth{state: :blind, checked_at: @now})
      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :blind})

      Req.Test.stub(:prowlarr_health, fn _conn ->
        flunk("current/1 must not read the roster while Prowlarr is down")
      end)

      assert %IndexerHealth{state: :blind} = IndexerHealth.current(client)
    end
  end
```

Add the alias at the top of the test file, beside the existing ones:

```elixir
  alias MediaCentaur.IntegrationAvailability
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/indexer_health_test.exs`
Expected: FAIL — `function MediaCentaur.Search.IndexerHealth.current/1 is undefined or private`.

- [ ] **Step 3: Implement `current/1`**

In `lib/media_centaur/search/indexer_health.ex`, add the alias beside the existing ones:

```elixir
  alias MediaCentaur.IntegrationAvailability
```

and add the function directly below `check/1`:

```elixir
  @doc """
  The observation a renderer should show: a fresh roster read while
  Prowlarr is up, the last recorded one while it is down.

  While Prowlarr is down `Search.ProbeJob` already reads the roster
  once a minute and writes this cache — a page that read it again would
  ask a dead server on its own schedule, learn nothing new, and mint a
  diagnostic event per failure. `cached/0` can still be `nil` for up to
  one probe cadence after an outage that no roster read discovered
  (a failed search reports `:prowlarr` down on its own); the Needs
  attention *incident* does not depend on this cache — it reads the
  availability value directly (`Search.IncidentContext`).
  """
  @spec current(Req.Request.t()) :: t() | nil
  def current(client \\ Prowlarr.default_client()) do
    if IntegrationAvailability.up?(:prowlarr), do: check(client), else: cached()
  end
```

Extend the moduledoc's `## Cache` section with one sentence:

```
  While Prowlarr is down the cache is refreshed by `Search.ProbeJob`
  rather than by whoever wants to render it — `current/1` is that read.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/indexer_health_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/search/indexer_health.ex test/media_centaur/search/indexer_health_test.exs
git commit -m "feat(search): the roster read is skipped while the probe owns it

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 2: `ViewModels.SearchOutage` — one sentence, one source

Today `GapVerdict` and `IncomingLive.PlanLogic` each carry their own `blind_reason/1` over an `IndexerHealth` struct — the same two clauses, twice, and both silent about a rejected API key (Prowlarr answering 401 reads as "unreachable"). Both move to the availability value, through one function.

**Files:**
- Create: `lib/media_centaur/acquisition/view_models/search_outage.ex`
- Modify: `lib/media_centaur/acquisition.ex` (exports)
- Test: `test/media_centaur/acquisition/view_models/search_outage_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/media_centaur/acquisition/view_models/search_outage_test.exs`:

```elixir
defmodule MediaCentaur.Acquisition.ViewModels.SearchOutageTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Acquisition.ViewModels.SearchOutage
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @t0 ~U[2026-09-18 10:00:00Z]

  defp down(reason), do: %Status{integration: :prowlarr, state: {:down, @t0, reason}, observed_at: @t0}

  describe "reason/1" do
    test "an up Prowlarr has no outage sentence" do
      assert SearchOutage.reason(%Status{integration: :prowlarr, state: :up}) == nil
    end

    test "each down reason reads mid-sentence" do
      assert SearchOutage.reason(down(:unreachable)) == "Prowlarr is unreachable"
      assert SearchOutage.reason(down(:rejected)) == "Prowlarr rejected your API key"
      assert SearchOutage.reason(down(:blind)) == "no indexers are answering"
    end

    test "a broken hand-off is not a search outage — the pursuit says that in its own words" do
      assert SearchOutage.reason(down(:client_unavailable)) == nil
    end
  end

  describe "reason/0" do
    test "reads the published Prowlarr availability" do
      assert SearchOutage.reason() == nil

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :rejected})

      assert SearchOutage.reason() == "Prowlarr rejected your API key"
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/search_outage_test.exs`
Expected: FAIL — `module MediaCentaur.Acquisition.ViewModels.SearchOutage is not available`.

- [ ] **Step 3: Write the module**

Create `lib/media_centaur/acquisition/view_models/search_outage.ex`:

```elixir
defmodule MediaCentaur.Acquisition.ViewModels.SearchOutage do
  @moduledoc """
  Why a search cannot answer right now, in the half-sentence the board
  reads mid-line — or `nil` while Prowlarr can answer.

  Two surfaces must never report an empty result as knowledge
  (UIDR-016): the gap banner (`ViewModels.GapVerdict`) and the board
  ticker's line for a live search (`IncomingLive.PlanLogic`). Both read
  this, so they cannot disagree, and the sentence outlives the last
  roster read — `MediaCentaur.IntegrationAvailability` stays down until
  a probe says otherwise, where the cached roster observation only ever
  said what someone last happened to see.

  Reads as "Couldn't check availability — Prowlarr is unreachable —
  Season 2".

  Pure (ADR-030) in `reason/1`; `reason/0` is the thin read of the
  published value.
  """

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  @doc "The sentence for the currently published Prowlarr availability."
  @spec reason() :: String.t() | nil
  def reason, do: :prowlarr |> IntegrationAvailability.status() |> reason()

  @doc "The sentence for one availability status, or `nil` when a search can still run."
  @spec reason(Status.t()) :: String.t() | nil
  def reason(%Status{state: {:down, _since, reason}}), do: line(reason)
  def reason(%Status{state: :up}), do: nil

  defp line(:unreachable), do: "Prowlarr is unreachable"
  defp line(:rejected), do: "Prowlarr rejected your API key"
  defp line(:blind), do: "no indexers are answering"

  # The hand-off has its own copy, on the pursuit that waits for it — a
  # search is unaffected by a download client Prowlarr cannot reach.
  defp line(:client_unavailable), do: nil
end
```

In `lib/media_centaur/acquisition.ex`, add to the `exports:` list, in alphabetical position among the other `ViewModels.*` entries (after `ViewModels.PursuitWithDownload`, before `ViewModels.Timeline`):

```elixir
      ViewModels.SearchOutage,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix compile --force` (the new export entry — see the rules), then
`~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/search_outage_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/view_models/search_outage.ex lib/media_centaur/acquisition.ex test/media_centaur/acquisition/view_models/search_outage_test.exs
git commit -m "feat(acquisition): one sentence says why a search cannot answer

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 3: The gap banner takes the sentence

**Files:**
- Modify: `lib/media_centaur/acquisition/view_models/gap_verdict.ex`
- Test: `test/media_centaur/acquisition/view_models/gap_verdict_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/media_centaur/acquisition/view_models/gap_verdict_test.exs`, change the shared builder (line ~160) from `search_health: nil` to `blind_reason: nil`:

```elixir
      Keyword.merge([gaps: ["Sample Movie"], movie?: true, blind_reason: nil, now: @now], overrides)
```

Replace the three blind-world assertions (around lines 279–295) with:

```elixir
    test "an unreachable provider outranks every other world" do
      verdict = build(evidence, blind_reason: "Prowlarr is unreachable")

      assert verdict.world == :blind
      assert verdict.headline =~ "Couldn't check availability — Prowlarr is unreachable"
    end

    test "blind indexers read as nobody answering" do
      verdict = build(evidence(%{}), blind_reason: "no indexers are answering")

      assert verdict.world == :blind
      assert verdict.headline =~ "no indexers are answering"
    end

    test "no outage sentence means the counts speak for themselves" do
      assert build(evidence(%{}), blind_reason: nil).world == :nothing_live
    end
```

And at line ~494, replace `search_health: %IndexerHealth{state: :unreachable, checked_at: @now},` with:

```elixir
          blind_reason: "Prowlarr is unreachable",
```

Delete the now-unused `blind_health/1` helper and the `alias MediaCentaur.Search.IndexerHealth` from the test file.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/gap_verdict_test.exs`
Expected: FAIL — `key :search_health not found` raised by `Keyword.fetch!/2` in `build/2`.

- [ ] **Step 3: Take the sentence instead of inferring it**

In `lib/media_centaur/acquisition/view_models/gap_verdict.ex`:

Remove `alias MediaCentaur.Search.IndexerHealth`.

Change the `build/2` doc line:

```elixir
  @doc """
  Builds the verdict. Options: `gaps` (unit labels), `movie?`,
  `blind_reason` (`ViewModels.SearchOutage.reason/0`'s sentence, or nil
  when a search can answer), `now` — plus, for the below-preference
  world (UIDR-029), `below` (`%{units: n, releases: n}` or nil),
  `wanted` and `covered`; and, for the calendar worlds,
  `release_window` (`ReleaseWindow.t()` or nil, read at `now`'s date).
  """
```

Change the first `cond` branch:

```elixir
      reason = Keyword.fetch!(opts, :blind_reason) ->
        blind(reason, gaps)
```

Delete the three private `blind_reason/1` clauses at the bottom of the module.

In the moduledoc's `:blind` bullet, name the source:

```
  * `:blind` — the search couldn't ask anyone (UIDR-016; outranks
    everything, keeps that record's copy verbatim). The sentence comes
    from `ViewModels.SearchOutage`, so it says what the availability
    value says and lasts exactly as long as the outage.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/gap_verdict_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/view_models/gap_verdict.ex test/media_centaur/acquisition/view_models/gap_verdict_test.exs
git commit -m "refactor(acquisition): the gap banner is handed its outage sentence

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 4: The board ticker takes the same sentence

**Files:**
- Modify: `lib/media_centaur_web/live/incoming_live/plan_logic.ex`
- Test: `test/media_centaur_web/live/incoming_live/plan_logic_test.exs`

- [ ] **Step 1: Write the failing test**

In `test/media_centaur_web/live/incoming_live/plan_logic_test.exs`, replace every `search_activity_line/2` call's second argument: an `%IndexerHealth{}` becomes the sentence, `nil` stays `nil`. Add this test to the `search_activity_line` describe block:

```elixir
    test "a zero-result live search during an outage reports the outage, never 0 found" do
      activity = %PlanEvents.SearchActivity{
        plan_id: "plan-1",
        term: "Sample Show S02",
        outcome: :live,
        result_count: 0
      }

      assert PlanLogic.search_activity_line(activity, "Prowlarr is unreachable") =~
               "couldn't reach any indexer"

      assert PlanLogic.search_activity_line(activity, nil) =~ "0 found"
    end
```

Remove the `alias MediaCentaur.Search.IndexerHealth` from the test file if nothing else uses it.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/plan_logic_test.exs`
Expected: FAIL — the outage branch falls through to "0 found" because `blind_reason/1` does not match a string.

- [ ] **Step 3: Take the sentence**

In `lib/media_centaur_web/live/incoming_live/plan_logic.ex`, remove `alias MediaCentaur.Search.IndexerHealth`, delete the three private `blind_reason/1` clauses, and rewrite the function:

```elixir
  @doc """
  The board ticker's line for a `PlanEvents.SearchActivity` — same
  honesty rule as the gap banner: a zero-result live search during an
  outage reports the outage, never "0 found". `outage` is
  `ViewModels.SearchOutage.reason/0`'s sentence, or nil.
  """
  @spec search_activity_line(PlanEvents.SearchActivity.t(), String.t() | nil) :: String.t()
  def search_activity_line(%PlanEvents.SearchActivity{} = activity, outage) do
    case {activity.outcome, activity.result_count, outage} do
      {:error, _count, _outage} ->
        "Search failed: #{activity.term}"

      {:corpus, count, _outage} ->
        "#{activity.term} — #{count} known (corpus)"

      {:live, 0, outage} when not is_nil(outage) ->
        "Searched: #{activity.term} — couldn't reach any indexer"

      {:live, count, _outage} ->
        "Searched: #{activity.term} — #{count} found"
    end
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live/plan_logic_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur_web/live/incoming_live/plan_logic.ex test/media_centaur_web/live/incoming_live/plan_logic_test.exs
git commit -m "refactor(web): the board ticker reads the same outage sentence

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 5: The Incoming page stops probing a down Prowlarr

**Files:**
- Modify: `lib/media_centaur/integration_availability.ex` (`subscribe/0`)
- Modify: `lib/media_centaur_web.ex` (Boundary dep)
- Modify: `lib/media_centaur_web/live/incoming_live.ex`
- Test: `test/media_centaur_web/live/incoming_live_test.exs`

The page keeps its `:search_health` assign — the Needs attention card and the plan modal still show which indexers are backed off, which is roster detail, not up/down. What changes: how that observation is fetched (`current/1`), a new `:search_outage` assign holding the sentence, and a subscription so recovery re-renders at once instead of at the next 30-second tick.

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur_web/live/incoming_live_test.exs` (a describe block of its own; follow the file's existing setup for a Prowlarr-ready page):

```elixir
  describe "a down Prowlarr" do
    test "the periodic health read asks nobody while Prowlarr is down", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/incoming")

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})

      Req.Test.stub(:prowlarr, fn _conn ->
        flunk("the page must not read the roster while Prowlarr is down")
      end)

      send(view.pid, :refresh_storage)
      assert render(view)
    end

    test "Prowlarr coming back re-reads the roster" do
      # The page subscribes to the availability topic; a change for
      # :prowlarr triggers a fresh read, and one for a hand-off does not
      # crash the page.
      {:ok, view, _html} = live(build_conn(), ~p"/incoming")

      send(view.pid, {:integration_availability_changed, {:handoff, :usenet}, :up})
      send(view.pid, {:integration_availability_changed, :prowlarr, :up})

      assert render(view)
    end
  end
```

Add `alias MediaCentaur.IntegrationAvailability` to the test file's aliases.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs`
Expected: FAIL — the first test flunks inside the stub (the page still calls `IndexerHealth.check/0`); the second raises `no function clause matching in MediaCentaurWeb.IncomingLive.handle_info/2`.

- [ ] **Step 3: Implement**

In `lib/media_centaur/integration_availability.ex`, add below `handoff_slots/0`:

```elixir
  @doc "Subscribes the calling process to `{:integration_availability_changed, integration, state}`."
  @spec subscribe() :: :ok
  def subscribe, do: Topics.subscribe(Topics.integration_availability_updates())
```

In `lib/media_centaur_web.ex`, add to the Boundary `deps:` list beside `MediaCentaur.IntegrationHealth`:

```elixir
      MediaCentaur.IntegrationAvailability,
```

In `lib/media_centaur_web/live/incoming_live.ex`:

Add the aliases beside the existing ones:

```elixir
  alias MediaCentaur.Acquisition.ViewModels.SearchOutage
  alias MediaCentaur.IntegrationAvailability
```

In `mount/3`, subscribe alongside the other always-live topics — change

```elixir
      [MediaCentaur.Library, Activities, Discovery]
```

to

```elixir
      [MediaCentaur.Library, Activities, Discovery, IntegrationAvailability]
```

Add the assign beside `search_health:`:

```elixir
         search_health: IndexerHealth.cached(),
         search_outage: SearchOutage.reason(),
```

Extract the health read so the availability change can run it alone. Replace `start_async_storage/1` with:

```elixir
  defp start_async_storage(socket) do
    socket
    |> start_async(:acquisition_storage, fn ->
      # Only drives a download can land on — a DB/image-cache-only drive can't
      # answer "do I have room for this grab?" (see DownloadStorage.media_dir_drives/1).
      DownloadStorage.media_dir_drives(Storage.measure_all())
    end)
    |> start_async_indexer_health()
  end

  # Two cheap Prowlarr reads (roster + back-offs) — the Needs attention
  # section's search card and the plan banner's honesty (UIDR-016) —
  # while Prowlarr is up. While it is down `current/0` returns the
  # probe's last observation and asks nobody.
  defp start_async_indexer_health(socket) do
    start_async(socket, :indexer_health, fn -> IndexerHealth.current() end)
  end
```

Update the async result so the sentence moves with the observation:

```elixir
  def handle_async(:indexer_health, {:ok, health}, socket) do
    {:noreply, assign(socket, search_health: health, search_outage: SearchOutage.reason())}
  end
```

Add the availability handlers beside the other `handle_info/2` clauses (before the `handle_info(%_{}, socket)` struct catch-all is fine — these match tuples):

```elixir
  # Prowlarr's availability moved: re-read the roster (free again once
  # it is up) and the sentence the board speaks.
  def handle_info({:integration_availability_changed, :prowlarr, _state}, socket) do
    {:noreply, socket |> assign(search_outage: SearchOutage.reason()) |> start_async_indexer_health()}
  end

  # A hand-off's availability is the Downloads tile's business — the
  # pursuit rows carry their own Waiting copy.
  def handle_info({:integration_availability_changed, _integration, _state}, socket),
    do: {:noreply, socket}
```

Refresh the sentence at the two places that re-read the cache:

```elixir
  defp maybe_reload_plan_board(socket, %PlanEvents.Changed{plan_id: plan_id}) do
    if socket.assigns.plan_param == plan_id do
      socket
      |> assign(search_health: IndexerHealth.cached(), search_outage: SearchOutage.reason())
      |> load_plan_board(plan_id)
    else
      socket
    end
  end
```

```elixir
  defp maybe_note_plan_activity(socket, %PlanEvents.SearchActivity{} = activity) do
    if socket.assigns.plan_param == activity.plan_id do
      # A zero-result live search just refreshed the IndexerHealth cache
      # (Corpus disambiguates empty-vs-blind at search time, UIDR-016) —
      # re-read both, so the ticker and the gap banner speak from the
      # same moment.
      outage = SearchOutage.reason()

      assign(socket,
        plan_last_activity: PlanLogic.search_activity_line(activity, outage),
        search_health: IndexerHealth.cached(),
        search_outage: outage
      )
    else
      socket
    end
  end
```

And hand the verdict the sentence — change the private function's parameter and its single call site (`load_plan_board/2`, around line 2824):

```elixir
  defp plan_gap_verdict(plan, board, outage, release_window) do
```

```elixir
      GapVerdict.build(
        Plans.Alternatives.gap_evidence(plan),
        gaps: board.gaps,
        movie?: board.movie?,
        blind_reason: outage,
        now: DateTime.utc_now(),
        below: below,
        wanted: board.wanted,
        covered: board.covered,
        release_window: release_window
      )
```

```elixir
        plan_gap_verdict(plan, board, socket.assigns.search_outage, socket.assigns.plan_release_window)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur_web/live/incoming_live_test.exs test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs test/media_centaur_web/live/plan_flow_test.exs`
Expected: PASS.

Also grep for any remaining caller that passes `search_health:` into `GapVerdict.build/2`:
Run: `grep -rn 'search_health' lib storybook`
Expected: only `needs_attention.ex`, `plan_modal.ex` (the roster card's attr), and `incoming_live.ex`'s assign/pass-through — no `GapVerdict.build` call.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/integration_availability.ex lib/media_centaur_web.ex lib/media_centaur_web/live/incoming_live.ex test/media_centaur_web/live/incoming_live_test.exs
git commit -m "feat(web): the Incoming page reads availability instead of probing it

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 6: A plan is held, not searched, while Prowlarr is down

`RunPlan` runs one corpus search per search-order step. During the 2026-09-17 outage every drop-planner tick enqueued plans that searched a dead Prowlarr and marked themselves in error. It now holds at the same cadence the probe runs at, mirroring `Jobs.PursueTarget`: an unconfigured Prowlarr is a long wait, a down one is the probe cadence.

**Files:**
- Modify: `lib/media_centaur/acquisition/jobs/run_plan.ex`
- Test: `test/media_centaur/acquisition/jobs/run_plan_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/acquisition/jobs/run_plan_test.exs` (top-level describe):

```elixir
  describe "held work — a known-down Prowlarr is not searched" do
    test "the plan stays planning, nothing is searched, and the job snoozes at the probe cadence" do
      {:ok, plan} = Plans.create_plan(plan_attrs(), unit_specs())

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})

      Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be searched while down") end)

      assert {:snooze, 60} =
               perform_job(MediaCentaur.Acquisition.Jobs.RunPlan, %{"plan_id" => plan.id})

      assert {:ok, %Plans.Plan{status: "planning"}} = Plans.fetch(plan.id)
    end

    test "an unconfigured Prowlarr waits an hour rather than at the probe cadence" do
      {:ok, plan} = Plans.create_plan(plan_attrs(), unit_specs())

      :ok = MediaCentaur.ProwlarrStubs.mark_unconfigured!()

      assert {:snooze, 3600} =
               perform_job(MediaCentaur.Acquisition.Jobs.RunPlan, %{"plan_id" => plan.id})
    end
  end
```

Reuse the file's existing plan-creation helpers rather than the placeholder `plan_attrs/0` / `unit_specs/0` names above — read the file's other tests and call whatever they call to get a `"planning"` plan. `perform_job/2` comes from `Oban.Testing` (already imported by `MediaCentaur.DataCase`; if it is not, call `MediaCentaur.Acquisition.Jobs.RunPlan.perform(%Oban.Job{args: %{"plan_id" => plan.id}})`). Add `alias MediaCentaur.IntegrationAvailability`. Note this file's `setup` writes the Prowlarr config `:persistent_term` directly and never records a passing connection test — replace that block with `:ok = MediaCentaur.ProwlarrStubs.mark_ready!()` so `Capabilities.prowlarr_ready?/0` is true, which the new gate reads.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/jobs/run_plan_test.exs`
Expected: FAIL — the stub flunks: the job searched Prowlarr.

- [ ] **Step 3: Hold at the top of the job**

In `lib/media_centaur/acquisition/jobs/run_plan.ex`, add the aliases:

```elixir
  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.ProbeJob
```

Add the module attribute beside the others:

```elixir
  # Matches `Jobs.PursueTarget`: a Prowlarr nobody configured is a
  # setup state, not an outage, and nothing probes it.
  @unconfigured_snooze_seconds 60 * 60
```

Replace `perform/1`:

```elixir
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"plan_id" => plan_id} = args}) do
    cond do
      not Capabilities.prowlarr_ready?() ->
        {:snooze, @unconfigured_snooze_seconds}

      not IntegrationAvailability.up?(:prowlarr) ->
        # Held: no search, no error on the plan. A snooze is a database
        # write, free, and it bounds the resumption to one probe cadence.
        {:snooze, ProbeJob.cadence_seconds()}

      true ->
        force? = Map.get(args, "force", false)

        case Plans.fetch(plan_id) do
          {:ok, %Plan{status: "planning"} = plan} -> run(plan, force?)
          {:ok, %Plan{}} -> {:ok, :not_planning}
          {:error, :not_found} -> {:ok, :not_found}
        end
    end
  end
```

Add to the moduledoc, after the first paragraph:

```
  The run is **held** while Prowlarr is unavailable
  (`MediaCentaur.IntegrationAvailability`): no search is spent, the plan
  stays `planning` — the board keeps its searching verdict — and the job
  snoozes at the probe cadence, so it resumes within a minute of
  Prowlarr answering again.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/jobs/run_plan_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/jobs/run_plan.ex test/media_centaur/acquisition/jobs/run_plan_test.exs
git commit -m "feat(acquisition): a plan is held while Prowlarr is down

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 7: The drop planner's tick is gated on availability

`Capabilities.prowlarr_ready?/0` is a configuration gate. Measured 2026-09-17: every young want was re-planned through a dead Prowlarr every 30 minutes because configuration said yes.

**Files:**
- Modify: `lib/media_centaur/acquisition/drop_planner.ex`
- Test: `test/media_centaur/acquisition/drop_planner_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/acquisition/drop_planner_test.exs`:

```elixir
  describe "held work — a known-down Prowlarr is not planned through" do
    test "the tick creates no plans and leaves the wants open" do
      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)

      {:changed, _state} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})

      Req.Test.stub(:prowlarr, fn _conn -> flunk("no planning while Prowlarr is down") end)

      assert :ok = DropPlanner.run_tick()
      assert Plans.list_drafts() == []
      assert [_want] = ReleaseTracking.list_open_wants()
    end
  end
```

Use whatever this file already calls to assert "no plan was created" and "the want is still open" — read its existing tests and copy those calls rather than the `Plans.list_drafts/0` placeholder above. Add `alias MediaCentaur.IntegrationAvailability`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/drop_planner_test.exs`
Expected: FAIL — a plan was created (the tick ran).

- [ ] **Step 3: Gate on availability**

In `lib/media_centaur/acquisition/drop_planner.ex`, replace the `alias MediaCentaur.Capabilities` with:

```elixir
  alias MediaCentaur.IntegrationAvailability
```

and the gate:

```elixir
  @doc """
  One pass over every watching item's open wants. Inert unless Prowlarr
  is configured **and** answering (`MediaCentaur.IntegrationAvailability`)
  — wants accumulate and nothing is lost: the next tick plans the
  backlog, and Prowlarr's recovery runs one immediately rather than
  waiting for the next sweep (`Reactor.Handlers.prowlarr_available/0`).
  """
  @spec run_tick(DateTime.t()) :: :ok
  def run_tick(now \\ DateTime.utc_now(:second)) do
    if IntegrationAvailability.available?(:prowlarr) do
```

Update the moduledoc's self-healing paragraph, which currently names a Prowlarr outage as something the next pass corrects:

```
  Batch is **state, not delta** — every tick re-derives from current
  open-want state, so the pipeline is self-healing: a missed tick, a
  discarded plan, a failed pursuit or a Prowlarr outage all correct
  themselves on the next pass (an outage holds the tick entirely, so
  nothing is spent while it lasts), and the mid-season backlog case is
  the weekly case with more wants.
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/drop_planner_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/drop_planner.ex test/media_centaur/acquisition/drop_planner_test.exs
git commit -m "feat(acquisition): the drop planner holds while Prowlarr is down

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 8: Recovery plans the backlog at once

Without this, wants held through an outage wait for the next 15-minute sweep after Prowlarr returns.

**Files:**
- Modify: `lib/media_centaur/acquisition/reactor.ex`
- Modify: `lib/media_centaur/acquisition/reactor/handlers.ex`
- Test: `test/media_centaur/acquisition/reactor/handlers_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/acquisition/reactor/handlers_test.exs`:

```elixir
  describe "prowlarr_available/0" do
    test "plans the wants that came due while Prowlarr was down" do
      item = create_tracked_show()
      create_aired_release(item, 1, 1, @last_month)

      assert :ok = Handlers.prowlarr_available()

      assert [_plan] = Plans.list_tracking_drafts()
    end
  end
```

Use this file's existing fixtures and its way of asserting a tracking plan exists (read the `tracking_sweep_completed/0` tests and copy their calls). Then add, in `test/media_centaur/acquisition/reactor/` or beside the Reactor's other coverage, a test that the GenServer routes the broadcast:

```elixir
  test "a Prowlarr recovery broadcast reaches the handler; other integrations are ignored" do
    start_supervised!(MediaCentaur.Acquisition.Reactor)

    send(Process.whereis(MediaCentaur.Acquisition.Reactor), {:integration_availability_changed, {:handoff, :usenet}, :up})
    send(Process.whereis(MediaCentaur.Acquisition.Reactor), {:integration_availability_changed, :prowlarr, {:down, DateTime.utc_now(), :unreachable}})

    # Still alive: neither message matches the recovery clause, and the
    # catch-all swallows them.
    assert Process.alive?(Process.whereis(MediaCentaur.Acquisition.Reactor))
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/reactor/handlers_test.exs`
Expected: FAIL — `function MediaCentaur.Acquisition.Reactor.Handlers.prowlarr_available/0 is undefined`.

- [ ] **Step 3: Implement**

In `lib/media_centaur/acquisition/reactor/handlers.ex`, add after `tracking_sweep_completed/0`:

```elixir
  @doc """
  Prowlarr answered again — plan the wants that came due while it was
  held, instead of waiting up to a sweep (15 minutes) for the next tick.
  Modes cannot have changed while Prowlarr was down, so this is the
  planner tick alone, not the full sweep pipeline.
  """
  @spec prowlarr_available() :: :ok
  def prowlarr_available, do: DropPlanner.run_tick()
```

Add to the moduledoc's public surface list:

```
  - `prowlarr_available/0` — run the drop planner tick on Prowlarr's
    recovery.
```

In `lib/media_centaur/acquisition/reactor.ex`, subscribe in `init/1`:

```elixir
    Topics.subscribe(Topics.release_tracking_updates())
    Topics.subscribe(Topics.acquisition_updates())
    Topics.subscribe(Topics.integration_availability_updates())
```

and add the clause above the catch-all:

```elixir
  def handle_info({:integration_availability_changed, :prowlarr, :up}, state) do
    Handlers.prowlarr_available()
    {:noreply, state}
  end
```

Add to the moduledoc's dispatch list:

```
  - `{:integration_availability_changed, :prowlarr, :up}` — Prowlarr
    recovered. Runs the drop planner tick at once
    (`Handlers.prowlarr_available/0`) so wants held through the outage
    are planned in seconds, not at the next sweep. Every other
    integration and every down transition falls through to the
    catch-all.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/reactor/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/reactor.ex lib/media_centaur/acquisition/reactor/handlers.ex test/media_centaur/acquisition/reactor/handlers_test.exs
git commit -m "feat(acquisition): Prowlarr's recovery plans the held backlog

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 9: The search incident lasts as long as the outage

Today a blind-indexer incident auto-resolves after 15 minutes without a fresh observation, which is why a three-day outage read as "nothing wrong" (memory `project-status-indexer-blindness-gap`). The probe now keeps the value current while down, so the staleness rule has nothing left to protect against — spec decision 2. A 401/403 also stops being reported as "unreachable": it is a rejected key, and it gets its own condition.

**Files:**
- Modify: `lib/media_centaur/search/incident_context.ex`
- Test: `test/media_centaur/search/incident_context_test.exs`

- [ ] **Step 1: Write the failing test**

Replace the whole of `test/media_centaur/search/incident_context_test.exs`:

```elixir
defmodule MediaCentaur.Search.IncidentContextTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.Search.IncidentContext

  @now ~U[2026-08-01 01:00:00Z]
  @grace_seconds 180

  defp decide(status), do: IncidentContext.decide(status, @now, @grace_seconds)

  defp up, do: %Status{integration: :prowlarr, state: :up, observed_at: @now}

  defp down(reason, since),
    do: %Status{integration: :prowlarr, state: {:down, since, reason}, observed_at: @now}

  test "an available Prowlarr is :ok" do
    assert decide(up()) == :ok
  end

  test "an unreachable provider past the grace window faults" do
    assert {:fault, :search_provider_unreachable, :warning, %{headline: headline}} =
             decide(down(:unreachable, ~U[2026-08-01 00:50:00Z]))

    assert headline == "Search provider unreachable"
  end

  test "blind indexers past the grace window fault as their own condition" do
    assert {:fault, :search_indexers_unavailable, :warning, %{headline: "No indexer available"}} =
             decide(down(:blind, ~U[2026-08-01 00:50:00Z]))
  end

  test "a rejected key is its own condition, not an unreachable provider" do
    assert {:fault, :search_provider_rejected, :warning, %{headline: headline}} =
             decide(down(:rejected, ~U[2026-08-01 00:50:00Z]))

    assert headline == "Search provider rejected the API key"
  end

  test "a fault younger than the grace window stays quiet" do
    assert decide(down(:blind, ~U[2026-08-01 00:59:00Z])) == :ok
  end

  test "an outage nobody has looked at in hours still faults — the probe keeps the value true" do
    assert {:fault, :search_indexers_unavailable, :warning, %{}} =
             decide(down(:blind, ~U[2026-07-29 00:00:00Z]))
  end

  test "a broken hand-off is the pursuit probe's condition, not search's" do
    assert decide(down(:client_unavailable, ~U[2026-08-01 00:50:00Z])) == :ok
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/incident_context_test.exs`
Expected: FAIL — `IncidentContext.decide/3` is undefined (the current one is `decide/4` over an `IndexerHealth`).

- [ ] **Step 3: Rewrite the probe**

Replace `lib/media_centaur/search/incident_context.ex`:

```elixir
defmodule MediaCentaur.Search.IncidentContext do
  @moduledoc """
  The acquisition subsystem's search-provider health probe — turns a
  sustained Prowlarr outage into a `:subsystem` incident condition
  (ADR-054, UIDR-016).

  ## Fault conditions

    * `:search_provider_unreachable` (**warning**) — the Prowlarr API
      itself can't be reached.
    * `:search_provider_rejected` (**warning**) — Prowlarr answers and
      refuses the API key (401/403). As useless as unreachable for held
      work, and a different thing to go fix.
    * `:search_indexers_unavailable` (**warning**) — Prowlarr answers,
      but every enabled indexer is backed off after failures; searches
      "succeed" with zero results without asking anyone.

  A partly backed-off roster (`IndexerHealth` `:degraded`) and an empty
  one (`:unconfigured`) leave `:prowlarr` available and never fault —
  the former is partial capability the Incoming page surfaces
  contextually, the latter is a setup state.

  ## Grace, and why there is no staleness rule

  Reads `MediaCentaur.IntegrationAvailability`, whose value is written
  by every real Prowlarr request and kept current while down by
  `Search.ProbeJob` — so the condition lasts exactly as long as the
  outage and clears within one probe of recovery. A grace window keeps
  one failed request from opening an incident on its own.

  This replaces the staleness rule an event-driven signal needed: the
  cached roster observation used to be treated as `:ok` once it aged
  past 15 minutes, on the reasoning that nothing was exercising search,
  which is why a three-day outage read as "nothing wrong". With a probe
  behind the value there is no unevidenced state left to resolve into.

  Composed into the `acquisition` component's single assessor by
  `MediaCentaur.Acquisition.IncidentContext` — the evaluator contract
  is one condition per component, and this, the hand-off probe and the
  download-client probe are all acquisition capabilities.
  """
  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status

  # Long enough that Prowlarr's own short first back-off (5 min ramp)
  # plus one probe can recover before an incident opens; aligned with
  # the download client's and the hand-off's grace.
  @grace_seconds 180

  @type fault :: {:fault, atom(), :warning, %{headline: String.t()}}

  @doc "Health probe polled (via the acquisition composite) by the diagnostics evaluator."
  @spec assess() :: :ok | fault()
  @impl true
  def assess do
    decide(IntegrationAvailability.status(:prowlarr), DateTime.utc_now(), @grace_seconds)
  end

  @doc "Pure fault decision over Prowlarr's availability."
  @spec decide(Status.t(), DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(%Status{state: {:down, since, reason}}, now, grace_seconds) do
    with {kind, headline} <- fault_for(reason),
         true <- DateTime.diff(now, since, :second) >= grace_seconds do
      {:fault, kind, :warning, %{headline: headline}}
    else
      _quiet -> :ok
    end
  end

  def decide(%Status{state: :up}, _now, _grace_seconds), do: :ok

  defp fault_for(:unreachable), do: {:search_provider_unreachable, "Search provider unreachable"}
  defp fault_for(:rejected), do: {:search_provider_rejected, "Search provider rejected the API key"}
  defp fault_for(:blind), do: {:search_indexers_unavailable, "No indexer available"}

  # The hand-off is `Pursuits.IncidentContext`'s condition — search is
  # unaffected by a download client Prowlarr cannot reach.
  defp fault_for(:client_unavailable), do: nil
end
```

Check `lib/media_centaur/search.ex`'s Boundary block: `MediaCentaur.IntegrationAvailability` is already a dep (step 1), so nothing changes there.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/incident_context_test.exs test/media_centaur/acquisition/incident_context_test.exs`
Expected: PASS. If `test/media_centaur/acquisition/incident_context_test.exs` builds its `@search_fault` from `Search.IncidentContext`, update it to the new shape; if it hand-writes the tuple (it does at line 8), it needs no change.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/search/incident_context.ex test/media_centaur/search/incident_context_test.exs
git commit -m "feat(search): the search incident lasts as long as the outage

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 10: Docs, wiki, campaign, precommit

**Files:**
- Modify: `lib/media_centaur/acquisition/corpus.ex` (comment)
- Modify: `../media-centaur.wiki/Troubleshooting.md`
- Modify: `campaigns/recurring-traffic-audit.md`

- [ ] **Step 1: Name the second thing the zero-result roster read does**

In `lib/media_centaur/acquisition/corpus.ex`, extend the comment above `blind?/0`:

```elixir
  # A zero-result 200 from Prowlarr is ambiguous: "no releases exist" or
  # "every indexer I'd ask is backed off / unreachable" look identical
  # (UIDR-016). Only the empty case pays for the disambiguating health
  # snapshot; a blind answer is an outage, and per this module's contract
  # an outage must never masquerade as fresh negative knowledge. The
  # check also lands the moment-of-truth observation in the
  # `IndexerHealth` cache, which the plan UI reads for the same honesty,
  # and writes `IntegrationAvailability` — so the search that proves
  # Prowlarr is blind is the one that holds everything else.
```

- [ ] **Step 2: Wiki — what the app does while Prowlarr is down**

In `../media-centaur.wiki/Troubleshooting.md`, in the **Acquisition (Prowlarr / Download client) not working** section, add this bullet after the existing "A pursuit reads *Waiting …*" bullet:

```markdown
- **Nothing is being searched or downloaded while Prowlarr is down** — that is deliberate. When Prowlarr stops answering, or answers but every indexer is backed off, the app stops asking: pursuits wait, plans stay on "Searching", and tracked titles are not re-planned. It checks once a minute, and everything held resumes within a minute of Prowlarr answering again — nothing is lost and no attempt is spent in the meantime. While it lasts, the Status page's Acquisition tile carries **Search provider unreachable**, **Search provider rejected the API key**, or **No indexer available**, and that warning stays up for as long as the outage does rather than fading out on its own.
```

And amend the last sentence of the existing "**A search finds 0 releases…**" bullet, which sends the reader to wait for a back-off retry, so it names the held state:

```markdown
… Wait for the retry, or fix the underlying failure (in Prowlarr's **System → Indexer health**; a VPN the indexer traffic routes through having dropped is a common cause) and press **Search again**. While every indexer is backed off the app itself stops searching — the banner reads **Couldn't check availability — no indexers are answering** — and starts again within a minute of one coming back.
```

Commit in the wiki repo:

```bash
cd ~/src/media-centaur/media-centaur.wiki
git add -A
git commit -m "wiki: what the app does while Prowlarr is down"
git push
```

- [ ] **Step 3: Campaign file**

In `campaigns/recurring-traffic-audit.md`:

- `last_updated: 2026-09-18`.
- **Status**: "Rollout step 2 of 5 landed 2026-09-18; step 3 is next and needs its own plan." List what exists in code after step 2 (the same shape as the step-1 paragraph): `IndexerHealth.current/1`; `ViewModels.SearchOutage` as the one outage sentence, read by `GapVerdict` and `PlanLogic`; the Incoming page's health read and its availability subscription; `RunPlan` and `DropPlanner` holds; `Reactor`'s recovery tick; `Search.IncidentContext` on the value with the staleness rule gone and `:search_provider_rejected` added.
- **Concrete defects found**: strike defect 4 (`Corpus.blind?/0` and Incoming's 30-second loop) — closed by `IndexerHealth.current/1`.
- **Inventory**: the rows for *Drop planner tick*, *Plan solve*, *Indexer health probe* and *Corpus re-search* get their post-step-2 gate.
- **Decisions made**: add `2026-09-18` — the search incident's 900 s staleness rule is retired (spec decision 2 implemented), and a Prowlarr 401/403 is its own condition rather than "unreachable".
- **Next steps**: drop items 1 and 2, renumber; step 3 (TMDB) is now the head.

- [ ] **Step 4: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASS, zero warnings. Fix everything it reports — in particular, Credo MC0009 if any component attr changed (none is expected: `search_health` stays the roster attr on `needs_attention` and `plan_modal`, so their stories do not change), and Boundary if a new export is missing.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/corpus.ex campaigns/recurring-traffic-audit.md
git commit -m "docs: availability step 2 landed — campaign status, the corpus's second job

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

## Verification after the last task

The step is done when all of this is true:

- `~/scripts/agents/agent-mix precommit` is green, zero warnings.
- `grep -rn 'IndexerHealth.check' lib` returns only `Search.ProbeJob`, `Corpus.blind?/0`, and `IndexerHealth.current/1` — no renderer probes Prowlarr directly.
- `grep -rn 'prowlarr_ready?' lib/media_centaur/acquisition` shows no *work* gated on configuration alone where an outage should hold it (the remaining hits are `PursueTarget`'s unconfigured branch and `RunPlan`'s, which are the deliberate two-halves reads).
- On the dev node, with Prowlarr's URL pointed at a dead port: a tracked title's tick creates no plan, `~/scripts/agents/mc-eval 'MediaCentaur.IntegrationAvailability.status(:prowlarr)'` reads down, the Incoming page's Prowlarr request count stops climbing in `MediaCentaur.HttpClient.Stats.snapshot().upstreams`, and the Acquisition tile carries the condition. Point it back: a plan appears within a minute without touching anything.

## Self-review against the spec

- **Held work table, `Jobs.RunPlan` row** — Task 6. Plan stays in its searching state; the board's verdict is unchanged by construction (the plan never leaves `planning`).
- **Held work table, `DropPlanner` row** — Task 7.
- **Held work table, `Corpus.blind?/0` row** — unchanged by design; the reporting half landed in step 1 (`IndexerHealth.check/1` calls `observe_roster/1`). Task 10 documents it.
- **Held work table, `IncomingLive` row** — Task 1 + Task 5.
- **Recovery, `Acquisition.Reactor`** — Task 8.
- **Recovery, `IncomingLive` re-render** — Task 5's subscription.
- **What the user sees, held plan** — Tasks 2–5: the blind verdict's reason now comes from the value.
- **Status, Needs attention** — Task 9, including spec decision 2 (persist while down).
- **Not in this step, by the spec's own rollout:** `:tmdb` (step 3), GitHub and relays (step 4), queue-monitor log transitions and the Connections tile's *down since* (step 5). `Plans.CommitPlan` keeps its one grab — that grab is the evidence that opens the hand-off, per the step-1 design.

---

## Execution record (2026-09-18)

Executed inline, one task per commit, `4b0b78c8..` — every task test-first,
red for the right reason before the implementation. What differed from the
plan as written:

- **Test seams.** `Oban.Testing.perform_job/3` is not imported by `DataCase`;
  `RunPlanTest` calls it through a local `run_plan_job/1`. The Reactor is not
  started in the test environment (`Application.pubsub_listeners(:test)` is
  `[]`), so the dispatch test runs one with `start_supervised!/1`.
- **Negative assertions.** A `flunk` inside a `Req.Test` stub is swallowed when
  the request happens inside a `start_async` task, so the Incoming-page tests
  record each Prowlarr call with a message to the test process and assert on
  the mailbox after the async is drained.
- **Fixture fallout the plan predicted for one file, found in seven.**
  `RunPlan`'s new unconfigured branch reads `Capabilities.prowlarr_ready?/0`,
  which is false for a fixture that writes Prowlarr's URL and key into the
  config `:persistent_term` without recording a passing connection test. Seven
  test files did exactly that and began snoozing instead of planning; each now
  calls `ProwlarrStubs.mark_ready!/0`: `run_plan_test`, `reactor/handlers_test`,
  `plans_test`, `plans/alternatives_gap_evidence_test`, `plans/commit_plan_test`,
  `title_states_test`, `incoming_badge_test`, `shell_badges_test`.
- **Storybook.** `plan_modal.story.exs` builds nine `GapVerdict`s and passed
  `search_health:` to each — they now pass `blind_reason:`. The component's own
  `search_health` attr is unchanged (it is the roster card's), so no story
  variation matrix moved.

Full suite 7,465 green; `reactor/handlers_test` clean over 16 consecutive runs.
