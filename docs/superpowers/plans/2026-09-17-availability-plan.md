# Availability, step 1 (Prowlarr and the hand-off) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pursuit never spends a Prowlarr search or grab while Prowlarr, or Prowlarr's link to the download client, is known down; it is held and resumes within a minute of recovery.

**Architecture:** One `MediaCentaur.IntegrationAvailability` value per integration (`:prowlarr`, `{:handoff, :usenet}`, `{:handoff, :torrent}`, `:tmdb` reserved for step 3) in `:persistent_term`, written only by the Prowlarr client's observer module from real request outcomes, kept fresh while down by an Oban probe job that makes free requests (indexer roster read; download-client test-all). `Jobs.PursueTarget` consults it before its search and before its grab and snoozes at the probe cadence when held. The pursuit's Waiting copy and the hand-off incident read the value instead of inferring from grab stamps. Spec: `docs/superpowers/specs/2026-09-17-availability-design.md`.

**Tech Stack:** Elixir/Phoenix, Oban 2.24 (Lite engine; `testing: :inline` in tests), Req + `Req.Test` stubs (`:prowlarr`), Boundary, ExUnit with `MediaCentaur.DataCase` / `MediaCentaur.Case`.

---

## Rules that apply to every task

- **Never run `mix` directly.** Every mix invocation is `~/scripts/agents/agent-mix <task>` (`~/scripts/agents/agent-mix test path`, `~/scripts/agents/agent-mix format`, …). A bare `mix` takes the running dev server down.
- **Test-first.** Write the test, run it red for the right reason, implement, run green.
- **Sandbox rules.** Tests that write `:persistent_term` (any `IntegrationAvailability.report/3` call) must be sync: `use MediaCentaur.Case, async: false` or `use MediaCentaur.DataCase` (already sync). Pure tests are `use MediaCentaur.Case, async: true`. The sandbox restores app-owned `:persistent_term` keys at check-in, so tests never clean up availability themselves.
- **Oban runs inline in tests.** `Oban.insert/1` executes the job at once in the calling process. When a test drives a *down* transition, the probe job runs immediately and hits the `:prowlarr` stub — the stub must answer `GET /api/v1/indexer`, `GET /api/v1/indexerstatus`, `GET /api/v1/downloadclient`, `POST /api/v1/downloadclient/testall`, or the test fails with an unanswered request.
- **Placeholders only** in tests and docs: "Sample Movie", never a real title.
- **Zero warnings.** `--warnings-as-errors` is on.
- The shell is fish: quote glob-like arguments.
- Commit after each task with the trailer line `Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF`. Never add a Co-Authored-By line.

## File map

| File | Responsibility |
|---|---|
| Create `lib/media_centaur/integration_availability/status.ex` | The value type and its pure fold |
| Create `lib/media_centaur/integration_availability.ex` | Store (`:persistent_term`), `status/1`, `up?/1`, `available?/1`, `report/3`, the change broadcast; Boundary context |
| Modify `lib/media_centaur/topics.ex` | `integration_availability_updates/0` |
| Create `lib/media_centaur/search/prowlarr_availability.ex` | The one writer for `:prowlarr` and the hand-offs: folds request, grab and roster outcomes; the hand-off probe; enqueues the probe job on a down transition |
| Modify `lib/media_centaur/search/prowlarr.ex` | `search/3` and `grab/2` report their outcome; `list_download_clients/1` exposes `id` and `protocol`; new `test_download_clients/1` |
| Modify `lib/media_centaur/search/indexer_health.ex` | `check/1` reports its observation |
| Create `lib/media_centaur/search/probe_job.ex` | Oban worker: probes while down, snoozes at the cadence, completes on up |
| Modify `lib/media_centaur/search.ex`, `lib/media_centaur/acquisition.ex` | Boundary deps |
| Modify `lib/media_centaur/acquisition/jobs/pursue_target.ex` | Hold before search and before grab; the discovering request's snoozes shortened to the cadence |
| Modify `lib/media_centaur/acquisition/pursuits.ex`, `lib/media_centaur/acquisition/view_models/pursuit_status.ex` | Held copy |
| Modify `lib/media_centaur/acquisition/pursuits/incident_context.ex` | Reads the hand-off availability instead of grab stamps |
| Modify `lib/media_centaur/integration_health.ex` | Moduledoc: probes now run on a schedule while an integration is down |
| Wiki `../media-centaur.wiki/Troubleshooting.md` | The pursuit Waiting entry |

---

### Task 1: `IntegrationAvailability.Status` — the value and its pure fold

**Files:**
- Create: `lib/media_centaur/integration_availability/status.ex`
- Test: `test/media_centaur/integration_availability/status_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.IntegrationIntegrationAvailability.StatusTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.IntegrationIntegrationAvailability.Status

  @t0 ~U[2026-09-17 20:00:00Z]
  @t1 ~U[2026-09-17 20:01:00Z]
  @t2 ~U[2026-09-17 20:02:00Z]

  describe "initial/2" do
    test "a never-observed integration is up" do
      status = Status.initial(:prowlarr, @t0)

      assert %Status{integration: :prowlarr, state: :up, observed_at: @t0, retry_at: nil} = status
      assert Status.up?(status)
    end
  end

  describe "fold/4" do
    test "up to up is unchanged and only moves observed_at" do
      status = Status.initial(:prowlarr, @t0)

      assert {:unchanged, %Status{state: :up, observed_at: @t1}} = Status.fold(status, :up, @t1, [])
    end

    test "up to down is a change dated now, carrying the reason" do
      status = Status.initial(:prowlarr, @t0)

      assert {:changed, %Status{state: {:down, @t1, :unreachable}, observed_at: @t1}} =
               Status.fold(status, {:down, :unreachable}, @t1, [])
    end

    test "down to down keeps the original onset, updates reason, observed_at and retry_at" do
      {:changed, down} = Status.fold(Status.initial(:prowlarr, @t0), {:down, :unreachable}, @t1, [])

      assert {:unchanged, folded} = Status.fold(down, {:down, :blind}, @t2, retry_at: @t2)
      assert folded.state == {:down, @t1, :blind}
      assert folded.observed_at == @t2
      assert folded.retry_at == @t2
      refute Status.up?(folded)
    end

    test "down to up is a change that clears retry_at" do
      {:changed, down} = Status.fold(Status.initial(:prowlarr, @t0), {:down, :blind}, @t1, retry_at: @t2)

      assert {:changed, %Status{state: :up, observed_at: @t2, retry_at: nil}} = Status.fold(down, :up, @t2, [])
    end
  end
end
```

- [ ] **Step 2: Run it red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/integration_availability/status_test.exs`
Expected: compile error — `MediaCentaur.IntegrationIntegrationAvailability.Status` is undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaur.IntegrationIntegrationAvailability.Status do
  @moduledoc """
  One integration's availability: `:up`, or `{:down, since, reason}`.

  A pure value. `fold/4` folds one observation into it and says whether
  the state changed, so the store (`MediaCentaur.IntegrationAvailability`) can
  write and broadcast only on transitions. The onset `since` survives
  consecutive down observations — one outage stays one outage even when
  its reason moves (unreachable, then blind, as a dead VPN presents).

  Reasons: `:unreachable` (transport error, 5xx, timeout), `:rejected`
  (401/403 — misconfigured is as useless as dead for held work),
  `:blind` (Prowlarr answers but every enabled indexer is backed off;
  `retry_at` carries Prowlarr's own retry time), `:client_unavailable`
  (Prowlarr cannot hand a release to the download client).
  """

  @enforce_keys [:integration, :state]
  defstruct [:integration, :state, :observed_at, :retry_at]

  @type integration :: :prowlarr | {:handoff, :usenet | :torrent} | :tmdb
  @type reason :: :unreachable | :rejected | :blind | :client_unavailable
  @type observation :: :up | {:down, reason()}
  @type state :: :up | {:down, DateTime.t(), reason()}
  @type t :: %__MODULE__{
          integration: integration(),
          state: state(),
          observed_at: DateTime.t(),
          retry_at: DateTime.t() | nil
        }

  @doc "The status before any observation: up."
  @spec initial(integration(), DateTime.t()) :: t()
  def initial(integration, %DateTime{} = now),
    do: %__MODULE__{integration: integration, state: :up, observed_at: now}

  @spec up?(t()) :: boolean()
  def up?(%__MODULE__{state: :up}), do: true
  def up?(%__MODULE__{}), do: false

  @doc """
  Folds one observation. Returns `{:changed, status}` on an up/down
  transition, `{:unchanged, status}` otherwise. `opts[:retry_at]` is
  kept on a down status and cleared on up.
  """
  @spec fold(t(), observation(), DateTime.t(), keyword()) :: {:changed | :unchanged, t()}
  def fold(%__MODULE__{state: :up} = status, :up, now, _opts),
    do: {:unchanged, %{status | observed_at: now}}

  def fold(%__MODULE__{state: {:down, _, _}} = status, :up, now, _opts),
    do: {:changed, %{status | state: :up, observed_at: now, retry_at: nil}}

  def fold(%__MODULE__{state: :up} = status, {:down, reason}, now, opts),
    do: {:changed, %{status | state: {:down, now, reason}, observed_at: now, retry_at: opts[:retry_at]}}

  def fold(%__MODULE__{state: {:down, since, _}} = status, {:down, reason}, now, opts),
    do: {:unchanged, %{status | state: {:down, since, reason}, observed_at: now, retry_at: opts[:retry_at]}}
end
```

- [ ] **Step 4: Run it green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/integration_availability/status_test.exs`
Expected: 5 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/integration_availability/status.ex test/media_centaur/integration_availability/status_test.exs
git commit -m "feat(availability): the per-integration status value and its fold" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 2: `Availability` — store, gate, broadcast

**Files:**
- Create: `lib/media_centaur/integration_availability.ex`
- Modify: `lib/media_centaur/topics.ex` (add one topic beside `capabilities_updates/0`, line ~182)
- Test: `test/media_centaur/integration_availability_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.IntegrationAvailabilityTest do
  # Sync: `report/3` writes `:persistent_term`, which the sandbox restores at check-in.
  use MediaCentaur.Case, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationIntegrationAvailability.Status
  alias MediaCentaur.Topics

  @t0 ~U[2026-09-17 20:00:00Z]
  @t1 ~U[2026-09-17 20:01:00Z]

  describe "status/1 and up?/1" do
    test "an integration nobody has observed is up" do
      assert %Status{integration: :prowlarr, state: :up} = IntegrationAvailability.status(:prowlarr)
      assert Availability.up?(:prowlarr)
      assert Availability.up?({:handoff, :usenet})
    end
  end

  describe "report/3" do
    test "the first down observation is a change, broadcast on the availability topic" do
      Topics.subscribe(Topics.integration_availability_updates())

      assert {:changed, {:down, @t0, :unreachable}} =
               IntegrationAvailability.report(:prowlarr, {:down, :unreachable}, now: @t0)

      assert_receive {:integration_availability_changed, :prowlarr, {:down, @t0, :unreachable}}
      refute Availability.up?(:prowlarr)
      assert Availability.up?({:handoff, :usenet})
    end

    test "a repeated down observation is unchanged and not broadcast, but is recorded" do
      Topics.subscribe(Topics.integration_availability_updates())
      {:changed, _} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable}, now: @t0)
      assert_receive {:integration_availability_changed, :prowlarr, _}

      assert :unchanged = IntegrationAvailability.report(:prowlarr, {:down, :blind}, now: @t1, retry_at: @t1)

      refute_receive {:integration_availability_changed, :prowlarr, _}, 50
      assert %Status{state: {:down, @t0, :blind}, observed_at: @t1, retry_at: @t1} = IntegrationAvailability.status(:prowlarr)
    end

    test "recovery is a change back to up" do
      Topics.subscribe(Topics.integration_availability_updates())
      {:changed, _} = IntegrationAvailability.report({:handoff, :torrent}, {:down, :client_unavailable}, now: @t0)
      assert_receive {:integration_availability_changed, {:handoff, :torrent}, _}

      assert {:changed, :up} = IntegrationAvailability.report({:handoff, :torrent}, :up, now: @t1)
      assert_receive {:integration_availability_changed, {:handoff, :torrent}, :up}
      assert Availability.up?({:handoff, :torrent})
    end

    test "an up observation on an up integration is unchanged and writes nothing" do
      before = IntegrationAvailability.status(:prowlarr)

      assert :unchanged = IntegrationAvailability.report(:prowlarr, :up, now: @t1)
      assert IntegrationAvailability.status(:prowlarr).observed_at == before.observed_at
    end
  end

  describe "available?/1" do
    test "is false while down even when the integration is configured" do
      {:changed, _} = IntegrationAvailability.report(:prowlarr, {:down, :rejected}, now: @t0)

      refute Availability.available?(:prowlarr)
    end

    test "is false for an unconfigured integration even when up" do
      # The test environment configures no Prowlarr and no download client.
      refute Availability.available?(:prowlarr)
      refute Availability.available?({:handoff, :usenet})
    end
  end
end
```

- [ ] **Step 2: Run it red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/integration_availability_test.exs`
Expected: compile error — `MediaCentaur.IntegrationAvailability` is undefined.

- [ ] **Step 3: Add the topic**

In `lib/media_centaur/topics.ex`, next to `def capabilities_updates, do: "capabilities:updates"`:

```elixir
  @doc "`{:integration_availability_changed, integration, state}` on every up/down transition (`MediaCentaur.IntegrationAvailability`)."
  def integration_availability_updates, do: "availability:updates"
```

- [ ] **Step 4: Implement the store**

```elixir
defmodule MediaCentaur.IntegrationAvailability do
  use Boundary, deps: [MediaCentaur.Capabilities], exports: [Status]

  @moduledoc """
  Whether a metered integration can do its job right now.

  Every metered outbound request is preceded by a free question — is
  the integration up? — answered here. One `Status` per integration lives
  in `:persistent_term`, runtime-only: a restart starts everything up
  and the first request or probe corrects it. Free probes keep a down
  integration's status current (`MediaCentaur.Search.ProbeJob`); while
  up, real requests are the evidence.

  **One writer per integration.** The module that owns the client calls
  `report/3` — `MediaCentaur.Search.ProwlarrAvailability` for `:prowlarr`
  and both hand-offs. Everyone else reads.

  `available?/1` is the gate callers use: configured (`Capabilities`,
  the durable half — credentials present and the last "Test connection"
  passed) **and** up (this module, the runtime half). Neither half is
  folded into the other: one is settings, the other observation.

  Writes happen on a transition and on every down observation (so
  `observed_at` says when a down integration was last probed); an up
  observation on an up integration writes nothing — `:persistent_term`
  updates cost a global scan, and Prowlarr answers many times a minute.
  Transitions broadcast `{:integration_availability_changed, integration, state}` on
  `Topics.integration_availability_updates/0`.
  """

  alias MediaCentaur.IntegrationIntegrationAvailability.Status
  alias MediaCentaur.{Capabilities, Topics}

  @integrations [:prowlarr, {:handoff, :usenet}, {:handoff, :torrent}, :tmdb]

  @doc "Every integration this module tracks."
  @spec integrations() :: [Status.integration()]
  def integrations, do: @integrations

  @spec status(Status.integration()) :: Status.t()
  def status(integration) when integration in @integrations do
    :persistent_term.get(key(integration), nil) || Status.initial(integration, DateTime.utc_now())
  end

  @spec up?(Status.integration()) :: boolean()
  def up?(integration), do: integration |> status() |> Status.up?()

  @doc "Configured and up. The gate before a metered request."
  @spec available?(Status.integration()) :: boolean()
  def available?(:prowlarr), do: Capabilities.prowlarr_ready?() and up?(:prowlarr)

  def available?({:handoff, slot} = integration),
    do: Capabilities.prowlarr_ready?() and Capabilities.client_ready?(slot) and up?(integration)

  def available?(:tmdb), do: Capabilities.tmdb_ready?() and up?(:tmdb)

  @doc """
  Folds one observation in. `opts`: `:now` (tests), `:retry_at` (kept
  on a down status). Returns `{:changed, state}` on a transition,
  `:unchanged` otherwise.
  """
  @spec report(Status.integration(), Status.observation(), keyword()) ::
          :unchanged | {:changed, Status.state()}
  def report(integration, observation, opts \\ []) when integration in @integrations do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    {verdict, next} = Status.fold(status(integration), observation, now, opts)

    case {verdict, next.state} do
      {:unchanged, :up} ->
        :unchanged

      {:unchanged, _down} ->
        :persistent_term.put(key(integration), next)
        :unchanged

      {:changed, state} ->
        :persistent_term.put(key(integration), next)
        Topics.publish(Topics.integration_availability_updates(), {:integration_availability_changed, integration, state})
        {:changed, state}
    end
  end

  defp key(integration), do: {__MODULE__, integration}
end
```

If the Boundary compiler reports that `MediaCentaur.Topics` must be listed, add it to `deps:` — `Capabilities` reaches it without listing, so it should not be needed.

- [ ] **Step 5: Run it green, then the sandbox test**

Run: `~/scripts/agents/agent-mix test test/media_centaur/integration_availability_test.exs test/media_centaur/global_state_sandbox_test.exs`
Expected: all green. If the sandbox test says the key `{MediaCentaur.IntegrationAvailability, _}` is not restored, register it the way `MediaCentaur.Search.IndexerHealth`'s cache key is registered in `test/support/global_state_sandbox.ex`, and re-run.

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/integration_availability.ex lib/media_centaur/topics.ex test/media_centaur/integration_availability_test.exs
git commit -m "feat(availability): the store, the gate, and the change broadcast" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 3: Prowlarr writes its own availability

**Files:**
- Create: `lib/media_centaur/search/prowlarr_availability.ex`
- Modify: `lib/media_centaur/search/prowlarr.ex` — `search/3` (~151-180), `grab/2` (~194-212), `parse_download_client/1` (~331), new `test_download_clients/1`
- Modify: `lib/media_centaur/search/indexer_health.ex` — `check/1` (~67)
- Modify: `lib/media_centaur/search.ex` — Boundary `deps:` add `MediaCentaur.IntegrationAvailability`, `MediaCentaur.Capabilities`; `exports:` add `ProwlarrAvailability`, `ProbeJob`
- Test: `test/media_centaur/search/prowlarr_availability_test.exs`

`ProbeJob` does not exist until Task 4. In this task `ProwlarrAvailability.enqueue_probe/1` is written against it, so **do Task 3 and Task 4 in one go before running the suite**, or stub the enqueue with a `@doc false` no-op that Task 4 replaces. Preferred: write Task 4's module first (it is small), then this task.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Search.ProwlarrAvailabilityTest do
  # Sync: reports write :persistent_term; Oban runs the probe job inline.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.{IndexerHealth, Prowlarr, ProwlarrAvailability}

  @roster_ok [%{"id" => 1, "name" => "Sample Indexer", "enable" => true, "protocol" => "usenet"}]

  # Answers every probe path so an inline probe run never trips the test.
  defp stub_prowlarr(answer) do
    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} -> Req.Test.json(conn, @roster_ok)
        {"GET", "/api/v1/indexerstatus"} -> Req.Test.json(conn, [])
        {"GET", "/api/v1/downloadclient"} -> Req.Test.json(conn, download_clients())
        {"POST", "/api/v1/downloadclient/testall"} -> Req.Test.json(conn, testall_all_valid())
        other -> answer.(conn, other)
      end
    end)
  end

  defp download_clients do
    [
      %{"id" => 1, "name" => "qBittorrent", "implementation" => "QBittorrent", "enable" => true, "protocol" => "torrent", "fields" => []},
      %{"id" => 2, "name" => "SABnzbd", "implementation" => "Sabnzbd", "enable" => true, "protocol" => "usenet", "fields" => []}
    ]
  end

  defp testall_all_valid, do: [%{"id" => 1, "isValid" => true, "validationFailures" => []}, %{"id" => 2, "isValid" => true, "validationFailures" => []}]

  defp client_unavailable(conn) do
    conn
    |> Plug.Conn.put_status(500)
    |> Req.Test.json(%{"description" => "NzbDrone.Core.Download.Clients.DownloadClientUnavailableException: Unable to connect to SABnzbd"})
  end

  describe "search/3 reports :prowlarr" do
    test "a transport error marks Prowlarr unreachable" do
      stub_prowlarr(fn conn, _ -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _} = Prowlarr.search("Sample Movie")
      assert %{state: {:down, _, :unreachable}} = IntegrationAvailability.status(:prowlarr)
    end

    test "a 401 marks Prowlarr rejected" do
      stub_prowlarr(fn conn, _ -> conn |> Plug.Conn.put_status(401) |> Req.Test.text("") end)

      assert {:error, _} = Prowlarr.search("Sample Movie")
      assert %{state: {:down, _, :rejected}} = IntegrationAvailability.status(:prowlarr)
    end

    test "a successful search marks Prowlarr up again" do
      {:changed, _} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      stub_prowlarr(fn conn, _ -> Req.Test.json(conn, []) end)

      assert {:ok, []} = Prowlarr.search("Sample Movie")
      assert Availability.up?(:prowlarr)
    end
  end

  describe "grab/2 reports the hand-off" do
    test "DownloadClientUnavailable marks the release's protocol hand-off down and Prowlarr up" do
      stub_prowlarr(fn conn, {"POST", "/api/v1/search"} -> client_unavailable(conn) end)
      result = %MediaCentaur.Search.SearchResult{guid: "g1", indexer_id: 1, title: "Sample.Movie.2005", protocol: :usenet}

      assert {:error, _} = Prowlarr.grab(result)
      assert %{state: {:down, _, :client_unavailable}} = IntegrationAvailability.status({:handoff, :usenet})
      assert Availability.up?({:handoff, :torrent})
      assert Availability.up?(:prowlarr)
    end

    test "a successful grab marks the hand-off up" do
      {:changed, _} = IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})
      stub_prowlarr(fn conn, {"POST", "/api/v1/search"} -> Req.Test.json(conn, %{}) end)
      result = %MediaCentaur.Search.SearchResult{guid: "g1", indexer_id: 1, title: "Sample.Movie.2005", protocol: :usenet}

      assert :ok = Prowlarr.grab(result)
      assert Availability.up?({:handoff, :usenet})
    end
  end

  describe "IndexerHealth.check/1 reports :prowlarr" do
    test "an unreachable roster marks Prowlarr unreachable; an ok roster marks it up" do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :timeout) end)
      assert %IndexerHealth{state: :unreachable} = IndexerHealth.check()
      assert %{state: {:down, _, :unreachable}} = IntegrationAvailability.status(:prowlarr)

      stub_prowlarr(fn conn, _ -> Req.Test.json(conn, []) end)
      assert %IndexerHealth{state: :ok} = IndexerHealth.check()
      assert Availability.up?(:prowlarr)
    end

    test "a blind roster marks Prowlarr down with Prowlarr's retry time" do
      retry_at = DateTime.add(DateTime.utc_now(:second), 600, :second)

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" -> Req.Test.json(conn, @roster_ok)
          "/api/v1/indexerstatus" -> Req.Test.json(conn, [%{"indexerId" => 1, "disabledTill" => DateTime.to_iso8601(retry_at)}])
        end
      end)

      assert %IndexerHealth{state: :blind} = IndexerHealth.check()
      assert %{state: {:down, _, :blind}, retry_at: ^retry_at} = IntegrationAvailability.status(:prowlarr)
    end
  end

  describe "probe_handoff/1" do
    test "folds test-all per slot: an invalid usenet client marks only that hand-off down" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/downloadclient"} -> Req.Test.json(conn, download_clients())
          {"POST", "/api/v1/downloadclient/testall"} ->
            Req.Test.json(conn, [%{"id" => 1, "isValid" => true, "validationFailures" => []}, %{"id" => 2, "isValid" => false, "validationFailures" => [%{"errorMessage" => "Unable to connect"}]}])
        end
      end)

      assert :ok = ProwlarrAvailability.probe_handoff()
      assert %{state: {:down, _, :client_unavailable}} = IntegrationAvailability.status({:handoff, :usenet})
      assert Availability.up?({:handoff, :torrent})
    end

    test "a slot with no enabled client on Prowlarr's side is left alone" do
      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/downloadclient"} -> Req.Test.json(conn, Enum.filter(download_clients(), &(&1["protocol"] == "usenet")))
          {"POST", "/api/v1/downloadclient/testall"} -> Req.Test.json(conn, [%{"id" => 2, "isValid" => true, "validationFailures" => []}])
        end
      end)

      {:changed, _} = IntegrationAvailability.report({:handoff, :torrent}, {:down, :client_unavailable})
      assert :ok = ProwlarrAvailability.probe_handoff()
      refute Availability.up?({:handoff, :torrent})
      assert Availability.up?({:handoff, :usenet})
    end
  end
end
```

Check the exact shape `IndexerHealth.classify/3` expects for a backed-off indexer (`indexer_snapshot/1` parses `/api/v1/indexerstatus` — read `lib/media_centaur/search/prowlarr.ex:254-290` and the existing `test/media_centaur/search/indexer_health_test.exs`), and adjust the blind fixture to it.

- [ ] **Step 2: Run it red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/prowlarr_availability_test.exs`
Expected: compile error — `ProwlarrAvailability` undefined.

- [ ] **Step 3: Implement the observer module**

```elixir
defmodule MediaCentaur.Search.ProwlarrAvailability do
  @moduledoc """
  The one writer of `:prowlarr` and hand-off availability
  (`MediaCentaur.IntegrationAvailability`).

  `Search.Prowlarr` calls `observe_request/1` after every search and
  `observe_grab/2` after every grab; `Search.IndexerHealth` calls
  `observe_roster/1` after every roster read. A grab that Prowlarr
  answers with `DownloadClientUnavailableException` says Prowlarr is up
  and the hand-off for that release's protocol is down.

  On a transition to down the owner enqueues `Search.ProbeJob`, which
  keeps the status fresh with free requests until the integration
  answers again. Nothing is enqueued for an unconfigured Prowlarr — a
  missing URL fails every request instantly and probing it would be
  noise.

  `probe_handoff/1` is the hand-off probe: one `downloadclient/testall`
  call, which reaches the clients from inside Prowlarr's network and
  touches no indexer, folded per slot.
  """

  alias MediaCentaur.{Capabilities, IntegrationAvailability}
  alias MediaCentaur.Search.{IndexerHealth, ProbeJob, Prowlarr}

  @slots [:usenet, :torrent]

  @doc "Folds a search or roster request outcome into `:prowlarr`."
  @spec observe_request(:ok | {:ok, term()} | {:error, term()}) :: :unchanged | {:changed, IntegrationAvailability.Status.state()}
  def observe_request(:ok), do: report(:prowlarr, :up)
  def observe_request({:ok, _}), do: report(:prowlarr, :up)
  def observe_request({:error, {:http_error, status, _body}}) when status in [401, 403], do: report(:prowlarr, {:down, :rejected})
  def observe_request({:error, {:http_error, status, _body}}) when status >= 500, do: report(:prowlarr, {:down, :unreachable})
  # Any other 4xx: Prowlarr is answering; the request was wrong.
  def observe_request({:error, {:http_error, _status, _body}}), do: report(:prowlarr, :up)
  def observe_request({:error, :missing_indexer_id}), do: :unchanged
  def observe_request({:error, _transport}), do: report(:prowlarr, {:down, :unreachable})

  @doc "Folds a grab outcome for a release of `protocol` into the hand-off, and into `:prowlarr`."
  @spec observe_grab(:ok | {:error, term()}, :usenet | :torrent | nil) :: :ok
  def observe_grab(:ok, protocol) do
    report(:prowlarr, :up)
    report_handoff(protocol, :up)
    :ok
  end

  def observe_grab({:error, reason} = error, protocol) do
    if Prowlarr.download_client_unavailable?(reason) do
      report(:prowlarr, :up)
      report_handoff(protocol, {:down, :client_unavailable})
    else
      observe_request(error)
    end

    :ok
  end

  @doc "Folds a roster observation into `:prowlarr`."
  @spec observe_roster(IndexerHealth.t()) :: :unchanged | {:changed, IntegrationAvailability.Status.state()}
  def observe_roster(%IndexerHealth{state: :unreachable}), do: report(:prowlarr, {:down, :unreachable})

  def observe_roster(%IndexerHealth{state: :blind, retry_at: retry_at}),
    do: report(:prowlarr, {:down, :blind}, retry_at: retry_at)

  def observe_roster(%IndexerHealth{}), do: report(:prowlarr, :up)

  @doc "The hand-off probe: test every download client Prowlarr has, fold per slot."
  @spec probe_handoff(Req.Request.t()) :: :ok | {:error, term()}
  def probe_handoff(client \\ Prowlarr.default_client()) do
    with {:ok, clients} <- Prowlarr.list_download_clients(client),
         {:ok, results} <- Prowlarr.test_download_clients(client) do
      valid_by_id = Map.new(results, &{&1.id, &1.valid?})

      for slot <- @slots do
        case Enum.filter(clients, &(&1.enabled and &1.protocol == slot)) do
          [] -> :unchanged
          enabled ->
            if Enum.all?(enabled, &Map.get(valid_by_id, &1.id, false)),
              do: IntegrationAvailability.report({:handoff, slot}, :up),
              else: IntegrationAvailability.report({:handoff, slot}, {:down, :client_unavailable})
        end
      end

      :ok
    else
      {:error, _reason} = error ->
        observe_request(error)
        error
    end
  end

  defp report_handoff(protocol, observation) when protocol in @slots do
    case IntegrationAvailability.report({:handoff, protocol}, observation) do
      {:changed, {:down, _, _}} = changed ->
        enqueue_probe("handoff")
        changed

      other ->
        other
    end
  end

  # Prowlarr omitted the protocol: nothing to attribute the outcome to.
  defp report_handoff(_protocol, _observation), do: :unchanged

  defp report(:prowlarr, observation, opts \\ []) do
    case IntegrationAvailability.report(:prowlarr, observation, opts) do
      {:changed, {:down, _, _}} = changed ->
        enqueue_probe("prowlarr")
        changed

      other ->
        other
    end
  end

  defp enqueue_probe(integration) do
    if Capabilities.prowlarr_ready?() do
      {:ok, _job} = %{integration: integration} |> ProbeJob.new(schedule_in: ProbeJob.cadence_seconds()) |> Oban.insert()
    end

    :ok
  end
end
```

- [ ] **Step 4: Hook the client and the roster**

In `lib/media_centaur/search/prowlarr.ex`:

`search/3` — bind the case result and observe it before returning:

```elixir
  def search(query, opts \\ [], client \\ default_client()) do
    # …existing params/log lines unchanged…
    result =
      case Req.get(client, url: "/api/v1/search", params: params) do
        # …existing clauses unchanged, each returning {:ok, results} | {:error, reason}…
      end

    ProwlarrAvailability.observe_request(result)
    result
  end
```

`grab/2` (the non-nil-indexer clause):

```elixir
  def grab(result, client) do
    Log.info(:acquisition, "prowlarr grab — #{result.title}")
    payload = %{"guid" => result.guid, "indexerId" => result.indexer_id}

    outcome =
      case Req.post(client, url: "/api/v1/search", json: payload) do
        # …existing three clauses unchanged…
      end

    ProwlarrAvailability.observe_grab(outcome, result.protocol)
    outcome
  end
```

`parse_download_client/1` — add the two fields the probe needs:

```elixir
    %{
      id: raw["id"],
      name: raw["name"],
      type: normalize_type(raw["implementation"]),
      protocol: normalize_protocol(raw["protocol"]),
      url: build_url(scheme, host, port),
      username: blank_to_nil(fields["username"]),
      enabled: raw["enable"] == true
    }
```

```elixir
  defp normalize_protocol("usenet"), do: :usenet
  defp normalize_protocol("torrent"), do: :torrent
  defp normalize_protocol(_), do: nil
```

New function, next to `list_download_clients/1`:

```elixir
  @doc """
  Prowlarr tests every configured download client from its own side and
  answers per client — the hand-off probe. Reaches the clients from
  inside Prowlarr's network; touches no indexer. ~10 ms.
  """
  @spec test_download_clients(Req.Request.t()) :: {:ok, [%{id: integer(), valid?: boolean()}]} | {:error, term()}
  def test_download_clients(client \\ default_client()) do
    case Req.post(client, url: "/api/v1/downloadclient/testall", receive_timeout: @ping_timeout_ms) do
      {:ok, %{status: 200, body: results}} when is_list(results) ->
        {:ok, Enum.map(results, &%{id: &1["id"], valid?: &1["isValid"] == true})}

      {:ok, %{status: status, body: body}} ->
        Log.warning(:acquisition, "prowlarr downloadclient/testall failed — status=#{status} body=#{inspect(body)}", mc_incident: :skip)
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Log.warning(:acquisition, "prowlarr downloadclient/testall error — #{inspect(reason)}", mc_incident: :skip)
        {:error, reason}
    end
  end
```

Add `alias MediaCentaur.Search.ProwlarrAvailability` at the top of `prowlarr.ex`.

In `lib/media_centaur/search/indexer_health.ex`, `check/1` — after the health is built and `cache_put/1` is called, add `ProwlarrAvailability.observe_roster(health)` (read the function; it ends by caching the classified or unreachable struct — observe the same struct it caches).

In `lib/media_centaur/search.ex` add `MediaCentaur.IntegrationAvailability` and `MediaCentaur.Capabilities` to `deps:` and `ProwlarrAvailability`, `ProbeJob` to `exports:`.

- [ ] **Step 5: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/prowlarr_availability_test.exs test/media_centaur/search/`
Expected: green. Existing Prowlarr tests that stub only `/api/v1/search` may now receive probe requests when a test drives a down transition (inline Oban) — extend those stubs to answer the four probe paths (see the `stub_prowlarr/1` helper above; copy it, do not share test helpers across files unless a support module already exists for Prowlarr stubs — grep `test/support` for `prowlarr` first and use it if present).

- [ ] **Step 6: Commit**

```bash
git add lib/media_centaur/search/prowlarr_availability.ex lib/media_centaur/search/prowlarr.ex lib/media_centaur/search/indexer_health.ex lib/media_centaur/search.ex test/media_centaur/search/
git commit -m "feat(search): Prowlarr writes its own availability and the hand-off's" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 4: `Search.ProbeJob` — probing while down

**Files:**
- Create: `lib/media_centaur/search/probe_job.ex`
- Test: `test/media_centaur/search/probe_job_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Search.ProbeJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.ProbeJob

  @roster_ok [%{"id" => 1, "name" => "Sample Indexer", "enable" => true, "protocol" => "usenet"}]

  describe "perform/1 for prowlarr" do
    test "snoozes at the cadence while Prowlarr stays unreachable" do
      {:changed, _} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:snooze, 60} = ProbeJob.perform(%Oban.Job{args: %{"integration" => "prowlarr"}})
      refute Availability.up?(:prowlarr)
    end

    test "completes once the roster answers" do
      {:changed, _} = IntegrationAvailability.report(:prowlarr, {:down, :unreachable})

      Req.Test.stub(:prowlarr, fn conn ->
        case conn.request_path do
          "/api/v1/indexer" -> Req.Test.json(conn, @roster_ok)
          "/api/v1/indexerstatus" -> Req.Test.json(conn, [])
        end
      end)

      assert :ok = ProbeJob.perform(%Oban.Job{args: %{"integration" => "prowlarr"}})
      assert Availability.up?(:prowlarr)
    end
  end

  describe "perform/1 for the hand-off" do
    test "snoozes while any hand-off is down, completes when both are up" do
      {:changed, _} = IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/downloadclient"} ->
            Req.Test.json(conn, [%{"id" => 2, "name" => "SABnzbd", "implementation" => "Sabnzbd", "enable" => true, "protocol" => "usenet", "fields" => []}])

          {"POST", "/api/v1/downloadclient/testall"} ->
            Req.Test.json(conn, [%{"id" => 2, "isValid" => false, "validationFailures" => []}])
        end
      end)

      assert {:snooze, 60} = ProbeJob.perform(%Oban.Job{args: %{"integration" => "handoff"}})

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/downloadclient"} ->
            Req.Test.json(conn, [%{"id" => 2, "name" => "SABnzbd", "implementation" => "Sabnzbd", "enable" => true, "protocol" => "usenet", "fields" => []}])

          {"POST", "/api/v1/downloadclient/testall"} ->
            Req.Test.json(conn, [%{"id" => 2, "isValid" => true, "validationFailures" => []}])
        end
      end)

      assert :ok = ProbeJob.perform(%Oban.Job{args: %{"integration" => "handoff"}})
      assert Availability.up?({:handoff, :usenet})
    end
  end

  describe "snooze_for/2" do
    test "waits for Prowlarr's own retry time when it is later than the cadence, capped at an hour" do
      now = ~U[2026-09-17 20:00:00Z]

      assert ProbeJob.snooze_for(nil, now) == 60
      assert ProbeJob.snooze_for(~U[2026-09-17 20:00:30Z], now) == 60
      assert ProbeJob.snooze_for(~U[2026-09-17 20:10:00Z], now) == 600
      assert ProbeJob.snooze_for(~U[2026-09-18 20:00:00Z], now) == 3600
    end
  end
end
```

- [ ] **Step 2: Run it red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/probe_job_test.exs`
Expected: compile error — `ProbeJob` undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Search.ProbeJob do
  @moduledoc """
  Keeps a down integration's availability fresh with free requests.

  Enqueued by `Search.ProwlarrAvailability` on a transition to down, one
  job per integration (`unique` on `integration`). Each run probes —
  the indexer roster read for `"prowlarr"`, `downloadclient/testall`
  for `"handoff"` — which reports through the same observers real
  requests use, then snoozes at the cadence while still down and
  completes on up. While up nothing probes: real requests are the
  evidence. For a blind Prowlarr the snooze waits for Prowlarr's own
  `retry_at` when that is later, capped at an hour so a stale time
  never silences probing.

  Oban is the timer because it already is one; a snooze is a database
  write, free. On the `:maintenance` queue (concurrency 1): a probe is
  milliseconds, and two at once would serialise harmlessly.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:integration], states: [:available, :scheduled, :executing, :retryable]]

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.{IndexerHealth, ProwlarrAvailability}

  @cadence_seconds 60
  @max_snooze_seconds 60 * 60
  @slots [:usenet, :torrent]

  @doc "Seconds between probes while down; also the snooze of held work."
  @spec cadence_seconds() :: pos_integer()
  def cadence_seconds, do: @cadence_seconds

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"integration" => "prowlarr"}}) do
    _health = IndexerHealth.check()

    case IntegrationAvailability.status(:prowlarr) do
      %{state: :up} -> :ok
      %{state: {:down, _, _}, retry_at: retry_at} -> {:snooze, snooze_for(retry_at, DateTime.utc_now())}
    end
  end

  def perform(%Oban.Job{args: %{"integration" => "handoff"}}) do
    _outcome = ProwlarrAvailability.probe_handoff()

    if Enum.all?(@slots, &Availability.up?({:handoff, &1})),
      do: :ok,
      else: {:snooze, @cadence_seconds}
  end

  @doc "The next probe delay: the cadence, or Prowlarr's own retry time when later, capped."
  @spec snooze_for(DateTime.t() | nil, DateTime.t()) :: pos_integer()
  def snooze_for(nil, _now), do: @cadence_seconds

  def snooze_for(%DateTime{} = retry_at, %DateTime{} = now) do
    retry_at |> DateTime.diff(now, :second) |> max(@cadence_seconds) |> min(@max_snooze_seconds)
  end
end
```

- [ ] **Step 4: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/probe_job_test.exs test/media_centaur/search/prowlarr_availability_test.exs`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/search/probe_job.ex test/media_centaur/search/probe_job_test.exs
git commit -m "feat(search): probe a down Prowlarr or hand-off with free requests" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 5: `PursueTarget` holds instead of spending

**Files:**
- Modify: `lib/media_centaur/acquisition/jobs/pursue_target.ex` — constants (~84-89), `pursue/3` (~158), `handle_found/5` (~324)
- Modify: `lib/media_centaur/acquisition.ex` — Boundary `deps:` add `MediaCentaur.IntegrationAvailability`
- Test: `test/media_centaur/acquisition/jobs/pursue_target_test.exs` (append a `describe`)

- [ ] **Step 1: Write the failing tests** (append to the existing file; reuse its `create_pursuit_with_target/1`, `movie_release/3`, `download_client_unavailable/1` helpers — read them first)

```elixir
  describe "held work — a known-down integration is not asked" do
    setup do
      # Prowlarr and a download client are configured in the test env
      # only when a test says so; these tests need both "ready" so the
      # gate is deciding on availability, not on configuration. Follow
      # the pattern the download-client outage describe uses to mark
      # Prowlarr ready (grep this file and test/support for
      # `save_integration` / `Capabilities`).
      :ok
    end

    test "Prowlarr down: no search, no grab, no attempt charged, snoozed at the probe cadence" do
      {:changed, _} = MediaCentaur.IntegrationAvailability.report(:prowlarr, {:down, :unreachable})
      target = seeking_movie_target()
      Req.Test.stub(:prowlarr, fn _conn -> flunk("Prowlarr must not be called while down") end)

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})

      reloaded = Repo.get!(MediaCentaur.Acquisition.Target, target.id)
      assert reloaded.attempt_count == target.attempt_count
      assert reloaded.last_attempt_outcome == target.last_attempt_outcome
    end

    test "hand-off down for the release's protocol: the search runs from the corpus, the grab does not" do
      {:changed, _} = MediaCentaur.IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable})
      target = seeking_movie_target()

      Req.Test.stub(:prowlarr, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/api/v1/search"} ->
            Req.Test.json(conn, [movie_release("Sample.Movie.2005.1080p.WEB-DL.H.264-GRP", "only-copy", %{grabs: 40, protocol: "usenet"})])

          {"POST", "/api/v1/search"} ->
            flunk("no grab while the hand-off is down")

          {"GET", "/api/v1/indexer"} -> Req.Test.json(conn, [])
          {"GET", "/api/v1/indexerstatus"} -> Req.Test.json(conn, [])
        end
      end)

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      assert Repo.get!(MediaCentaur.Acquisition.Target, target.id).attempt_count == target.attempt_count
    end

    test "the discovering grab still snoozes only at the probe cadence" do
      stub_grab_reply(&download_client_unavailable/1)
      target = seeking_movie_target()

      assert {:snooze, 60} = PursueTarget.perform(%Oban.Job{args: %{"target_id" => target.id}})
      assert Repo.get!(MediaCentaur.Acquisition.Target, target.id).last_attempt_outcome == "download_client_unavailable"
      refute MediaCentaur.IntegrationAvailability.up?({:handoff, :usenet})
    end
  end
```

Check `movie_release/3` accepts a `protocol` override; if not, add it to the helper (it builds the Prowlarr result JSON — the field is `"protocol"`). The existing test "a 5xx from grab keeps the attempt count and snoozes briefly" asserts the old 15-minute snooze — update its expectation to `60`.

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/jobs/pursue_target_test.exs`
Expected: the three new tests fail — the first flunks because Prowlarr was called; the second flunks on the grab; the third gets `{:snooze, 900}`.

- [ ] **Step 3: Implement**

Constants — both discovering snoozes become the cadence (the next run is held by availability; the discovering request must not be the slow one):

```elixir
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.ProbeJob

  @snooze_cap_hours 24
  # An unconfigured Prowlarr fails every request instantly; nothing to
  # do until Settings change. Not availability's business.
  @unconfigured_snooze_seconds 60 * 60
  @needs_decision_prompt "Pick a release."
  @pack_prompt "Only a pack has this episode. Picking it downloads the whole pack."
```

Remove `@prowlarr_error_snooze_seconds` and `@download_client_snooze_seconds`; the two `handle_*` calls pass `ProbeJob.cadence_seconds()` instead:

```elixir
  defp handle_prowlarr_error(target, reason) do
    Log.warning(:acquisition, "acquisition prowlarr error — #{inspect(reason)}")
    handle_infrastructure_failure(target, "prowlarr_error", ProbeJob.cadence_seconds())
  end
```

and in `handle_found/5`'s outage branch: `handle_infrastructure_failure(target, "download_client_unavailable", ProbeJob.cadence_seconds())`.

`pursue/3` — the gate before the search:

```elixir
  defp pursue(%Target{} = target, %Pursuit{} = pursuit, %Unit{} = unit) do
    cond do
      not Capabilities.prowlarr_ready?() ->
        Log.info(:acquisition, "acquisition waiting — #{target.title} (Prowlarr is not configured)")
        {:snooze, @unconfigured_snooze_seconds}

      not Availability.up?(:prowlarr) ->
        hold(target, :prowlarr)

      true ->
        search_and_act(target, pursuit, unit)
    end
  end

  # The body `pursue/3` had before the gate, unchanged.
  defp search_and_act(%Target{} = target, %Pursuit{} = pursuit, %Unit{} = unit) do
    Log.info(:acquisition, "acquisition search — #{target.title} (attempt #{target.attempt_count + 1})")
    prefs = effective_prefs(pursuit)
    criteria = pursuit |> Recipe.for_unit(unit) |> Recipe.to_criteria() |> Cours.with_run(pursuit.tmdb_id)

    case search_until_match(unit, criteria, QueryBuilder.build(criteria), prefs) do
      {:ok, best} -> handle_found(target, pursuit, unit, criteria, best)
      {:needs_decision, _results} -> handle_needs_decision(target, pursuit, unit)
      {:no_match, outcome} -> handle_no_results(target, pursuit, unit, criteria, outcome)
      {:error, reason} -> handle_prowlarr_error(target, reason)
    end
  end

  # Held: no request, no attempt, no stamp. Ask again at the probe
  # cadence; a snooze is a database write, free.
  defp hold(%Target{} = target, integration) do
    Log.info(:acquisition, "acquisition held — #{target.title} (#{inspect(integration)} is down)")
    {:snooze, ProbeJob.cadence_seconds()}
  end
```

`handle_found/5` — the gate before the grab:

```elixir
  defp handle_found(target, pursuit, unit, criteria, %SearchResult{} = result) do
    if held_handoff?(result) do
      hold(target, {:handoff, result.protocol})
    else
      grab_found(target, pursuit, unit, criteria, result)
    end
  end

  # A result without a protocol cannot be attributed to a slot: grab,
  # and let the outcome be the evidence.
  defp held_handoff?(%SearchResult{protocol: protocol}) when protocol in [:usenet, :torrent],
    do: not Availability.up?({:handoff, protocol})

  defp held_handoff?(%SearchResult{}), do: false

  # The body `handle_found/5` had before the gate, unchanged.
  defp grab_found(target, pursuit, unit, criteria, result) do
    case Prowlarr.grab(result) do
      # …existing clauses…
    end
  end
```

Add `alias MediaCentaur.Capabilities` if not already aliased. Add `MediaCentaur.IntegrationAvailability` to `lib/media_centaur/acquisition.ex` `deps:`.

Confirm the test environment's `Capabilities.prowlarr_ready?/0` for these tests: the existing outage tests reach the grab, so Prowlarr is ready there — reuse whatever they do (the `setup` hint above). If the existing tests rely on Prowlarr being *unconfigured* being irrelevant today, the new `@unconfigured_snooze_seconds` branch will surface it as `{:snooze, 3600}` — then mark Prowlarr ready in those tests the same way the Incoming page tests do (`Capabilities.save_integration/2` with a URL and key).

- [ ] **Step 4: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/jobs/pursue_target_test.exs test/media_centaur/acquisition/`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/jobs/pursue_target.ex lib/media_centaur/acquisition.ex test/media_centaur/acquisition/jobs/pursue_target_test.exs
git commit -m "feat(acquisition): a pursuit is held while Prowlarr or the hand-off is down" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 6: The Waiting copy reads availability

**Files:**
- Modify: `lib/media_centaur/acquisition/view_models/pursuit_status.ex` — `derive` for a seeking target (~300-312 and the clause that calls `outage_description/1` / `searching_description/1`)
- Modify: `lib/media_centaur/acquisition/pursuits.ex` — `status_from/2` (~389) and `refresh_status_download/2` (~346) pass the held integration
- Test: `test/media_centaur/acquisition/view_models/pursuit_status_test.exs` (append)

- [ ] **Step 1: Write the failing test** (append beside the existing seeking-target tests; use their `build_*` factories)

```elixir
  describe "derive/5 — held on a down integration" do
    test "Prowlarr down reads as waiting on Prowlarr, with no attempt clock" do
      pursuit = build_pursuit(%{state: "active", title: "Sample Movie"})
      unit = build_unit(%{pursuit_id: pursuit.id})
      target = build_target(%{status: "seeking", next_attempt_at: nil, attempt_count: 2})

      {action, next_step, actions} = PursuitStatus.derive(pursuit, unit, target, nil, :none, held: :prowlarr)

      assert action.verb == "Waiting"
      assert action.description == "Prowlarr is unreachable. Resumes when it answers again."
      assert next_step == nil
      assert :cancel in actions
    end

    test "the hand-off down reads as waiting on the download client" do
      pursuit = build_pursuit(%{state: "active", title: "Sample Movie"})
      unit = build_unit(%{pursuit_id: pursuit.id})
      target = build_target(%{status: "seeking", next_attempt_at: nil, attempt_count: 0})

      {action, _next_step, _actions} = PursuitStatus.derive(pursuit, unit, target, nil, :none, held: :handoff)

      assert action.verb == "Waiting"
      assert action.description == "Prowlarr could not reach your download client. Resumes when it can."
    end

    test "nothing held keeps today's copy" do
      pursuit = build_pursuit(%{state: "active", title: "Sample Movie"})
      unit = build_unit(%{pursuit_id: pursuit.id})
      target = build_target(%{status: "seeking", next_attempt_at: nil, attempt_count: 0})

      {action, _next_step, _actions} = PursuitStatus.derive(pursuit, unit, target, nil, :none, held: nil)

      assert action.description == "Looking for an acceptable release (attempt 1)."
    end
  end
```

Read the file's existing tests and factories first; match their names (`build_pursuit`, `build_unit`, `build_target` — grep `test/support/factory.ex`), and match the exact `derive` arity the file exports (the spec above assumes a `location` argument exists per the `derive/5` clause at ~277; add `opts` as a sixth argument with `held: nil` default).

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/pursuit_status_test.exs`
Expected: the new tests fail — `derive/6` undefined, or old copy.

- [ ] **Step 3: Implement**

In `pursuit_status.ex`, give `derive` a trailing `opts \\ []` on the public arity and thread `Keyword.get(opts, :held)` to the seeking clause. Beside `outage_description/1`:

```elixir
  # Held before any attempt: no clock, because it resumes on recovery,
  # not on a timer. Verb and severity match the outage copy.
  defp held_description(:prowlarr), do: "Prowlarr is unreachable. Resumes when it answers again."
  defp held_description(:handoff), do: "Prowlarr could not reach your download client. Resumes when it can."
```

In the seeking-target `derive` clause (the one that today chooses between `outage_description/1` and `searching_description/1` from `last_attempt_outcome`), check `held` first:

```elixir
      description =
        case held do
          nil -> seeking_or_outage_description(target)
          integration -> held_description(integration)
        end
```

with `verb: "Waiting"` and `next_step: nil` when held. Keep the existing branch for `held == nil` byte-for-byte.

In `pursuits.ex`, `status_from/2` and `refresh_status_download/2` compute the held integration once and pass it:

```elixir
  # The Waiting copy's reason. Prowlarr down outranks a hand-off, and any
  # configured slot's hand-off counts: a seeking target has not chosen a
  # protocol yet.
  defp held_integration do
    cond do
      not Availability.up?(:prowlarr) -> :prowlarr
      Enum.any?([:usenet, :torrent], &(Capabilities.client_ready?(&1) and not Availability.up?({:handoff, &1}))) -> :handoff
      true -> nil
    end
  end
```

and `PursuitStatus.derive(pursuit, unit, target, queue_item, location, held: held_integration())` at both call sites.

- [ ] **Step 4: Run green**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/view_models/pursuit_status_test.exs test/media_centaur/acquisition/pursuits_test.exs test/media_centaur_web/live/incoming_live_pursuit_modal_test.exs`
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/view_models/pursuit_status.ex lib/media_centaur/acquisition/pursuits.ex test/media_centaur/acquisition/view_models/pursuit_status_test.exs
git commit -m "feat(acquisition): a held pursuit says which integration it waits on" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 7: The hand-off incident reads availability

**Files:**
- Modify: `lib/media_centaur/acquisition/pursuits/incident_context.ex`
- Test: `test/media_centaur/acquisition/pursuits/incident_context_test.exs`

- [ ] **Step 1: Write the failing test** (replace the file's `decide/4` tests with these; the stamp inference goes away)

```elixir
defmodule MediaCentaur.Acquisition.Pursuits.IncidentContextTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.IncidentContext
  alias MediaCentaur.IntegrationIntegrationAvailability.Status

  @t0 ~U[2026-09-17 20:00:00Z]

  defp down(slot, since), do: %Status{integration: {:handoff, slot}, state: {:down, since, :client_unavailable}, observed_at: since}
  defp up(slot), do: %Status{integration: {:handoff, slot}, state: :up, observed_at: @t0}

  describe "decide/3" do
    test "both hand-offs up is ok" do
      assert :ok = IncidentContext.decide([up(:usenet), up(:torrent)], @t0, 180)
    end

    test "a hand-off down inside the grace window is not yet a fault" do
      now = DateTime.add(@t0, 60, :second)
      assert :ok = IncidentContext.decide([down(:usenet, @t0), up(:torrent)], now, 180)
    end

    test "a hand-off down past the grace window is a warning" do
      now = DateTime.add(@t0, 181, :second)

      assert {:fault, :download_client_handoff_failed, :warning, %{headline: "Prowlarr could not hand releases to the download client"}} =
               IncidentContext.decide([up(:usenet), down(:torrent, @t0)], now, 180)
    end
  end
end
```

- [ ] **Step 2: Run red**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/pursuits/incident_context_test.exs`
Expected: `decide/3` undefined.

- [ ] **Step 3: Implement** — replace the module body:

```elixir
defmodule MediaCentaur.Acquisition.Pursuits.IncidentContext do
  @moduledoc """
  The pursuit side's health probe for the hop the app cannot see
  directly: Prowlarr handing a release to the download client. The
  `assess/0` that `Acquisition.IncidentContext` composes into the
  `acquisition` component's single condition (ADR-054).

  Reads `MediaCentaur.IntegrationAvailability` for both hand-off slots. The value
  is written by the grab that discovers an outage and kept fresh by
  `Search.ProbeJob` while down, so the fault lasts exactly as long as
  the outage and clears within one probe of recovery. A grace window
  keeps one failed grab from opening an incident on its own.
  """

  @behaviour MediaCentaur.ErrorReports.IncidentContext

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationIntegrationAvailability.Status

  # Aligned with the download client's and search's grace.
  @grace_seconds 180
  @slots [:usenet, :torrent]

  @type fault :: {:fault, :download_client_handoff_failed, :warning, %{headline: String.t()}}

  @doc "Health probe polled (via the acquisition composite) by the diagnostics evaluator."
  @spec assess() :: :ok | fault()
  @impl true
  def assess do
    @slots
    |> Enum.map(&IntegrationAvailability.status({:handoff, &1}))
    |> decide(DateTime.utc_now(), @grace_seconds)
  end

  @doc "Pure fault decision over the hand-off statuses."
  @spec decide([Status.t()], DateTime.t(), pos_integer()) :: :ok | fault()
  def decide(statuses, now, grace_seconds) do
    if Enum.any?(statuses, &down_past_grace?(&1, now, grace_seconds)) do
      {:fault, :download_client_handoff_failed, :warning,
       %{headline: "Prowlarr could not hand releases to the download client"}}
    else
      :ok
    end
  end

  defp down_past_grace?(%Status{state: {:down, since, _reason}}, now, grace_seconds),
    do: DateTime.diff(now, since, :second) >= grace_seconds

  defp down_past_grace?(%Status{state: :up}, _now, _grace_seconds), do: false
end
```

- [ ] **Step 4: Run green, plus the acquisition incident composite and the Status page smoke**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/pursuits/incident_context_test.exs test/media_centaur/acquisition/incident_context_test.exs test/media_centaur_web/page_smoke_test.exs`
Expected: green. If `test/media_centaur/acquisition/incident_context_test.exs` drove the hand-off fault through grab stamps, rewrite that case to `IntegrationAvailability.report({:handoff, :usenet}, {:down, :client_unavailable}, now: <past the grace>)` in a sync test.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/pursuits/incident_context.ex test/media_centaur/acquisition/
git commit -m "feat(acquisition): the hand-off incident reads availability, not grab stamps" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 8: Docs, wiki, precommit

**Files:**
- Modify: `lib/media_centaur/integration_health.ex` — moduledoc line ~19 ("Nothing is probed")
- Modify: `campaigns/recurring-traffic-audit.md` — Status and Next steps
- Wiki: `../media-centaur.wiki/Troubleshooting.md` — the pursuit Waiting bullet (~line 141)

- [ ] **Step 1: `IntegrationHealth` moduledoc** — replace the sentence that says nothing is probed on a schedule with:

```
  Nothing here probes on a schedule. The one scheduled probe in the app is
  `MediaCentaur.Search.ProbeJob`, which runs only while an integration is
  known down (`MediaCentaur.IntegrationAvailability`) and stops on recovery.
```

- [ ] **Step 2: Wiki** — replace the Waiting bullet's second and third sentences ("The release is kept and retried every 15 minutes; nothing counts against the pursuit's attempts, and picking a different release will not help.") with:

```
The pursuit is held: nothing is searched or grabbed until Prowlarr can reach the client again, which the app checks once a minute; nothing counts against the pursuit's attempts, and picking a different release will not help. A pursuit that reads "Waiting — Prowlarr is unreachable" is held the same way until Prowlarr answers.
```

and the closing clause ("both clear on the next successful grab, or half an hour after the last failed retry") with:

```
both clear within a minute of the link recovering.
```

Commit the wiki in its own repo: `cd ~/src/media-centaur/media-centaur.wiki && git add Troubleshooting.md && git commit -m "wiki: a held pursuit resumes within a minute of Prowlarr recovering"` (with the session trailer). Do not push.

- [ ] **Step 3: Campaign** — in `campaigns/recurring-traffic-audit.md` Status, add: "Rollout step 1 landed <date>: Availability, Prowlarr and hand-off writers, ProbeJob, PursueTarget holds, Waiting copy, hand-off incident." In Next steps mark step 1 of the rollout done.

- [ ] **Step 4: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: format clean, credo no issues, boundaries pass, tests green. Fix everything it reports; zero warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/integration_health.ex campaigns/recurring-traffic-audit.md
git commit -m "docs: availability step 1 — moduledoc, campaign status" -m "Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

## Self-review against the spec

- Value, one writer, write-on-transition, broadcast — Tasks 1–2.
- Prowlarr opens on transport/5xx/401/403 and roster `:unreachable`/`:blind` (with `retry_at`), closes on any success — Task 3.
- Hand-off opens on `DownloadClientUnavailable` per protocol, probe is test-all, closes on valid probe or successful grab — Tasks 3–4.
- Probe job on `:maintenance`, unique per integration, snoozes at cadence, honours `retry_at` capped — Task 4.
- PursueTarget holds before search and before grab, no attempt, no stamp, snooze at cadence; discovering snoozes shortened; unconfigured Prowlarr is not held at the cadence — Task 5.
- CommitPlan-then-pursuit double grab closes by construction (the pursuit's grab step is gated) — Task 5, no separate code.
- Waiting copy from availability — Task 6.
- Hand-off incident from availability with grace — Task 7.
- `IntegrationHealth` moduledoc, wiki, campaign — Task 8.
- Deferred to step 2: `RunPlan`, `DropPlanner` gate, `Corpus.blind?` report path (already reports via `IndexerHealth.check` in Task 3), `IncomingLive` loop reading status while down, `GapVerdict` reason, `Reactor` recovery tick, `Search.IncidentContext` without staleness. Step 3: `:tmdb`. Step 5: queue-monitor log transitions, Connections tile.
