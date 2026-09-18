# Availability, step 3 (TMDB) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While TMDB cannot answer, nothing asks it on a schedule: the release-tracking refresh cycle and the artwork warm hold, and the held cycle runs within one probe of recovery instead of waiting out the 6-hour interval.

**Architecture:** The same shape steps 1 and 2 built for Prowlarr, applied to `:tmdb`. `MediaCentaur.TMDB.Availability` is the one writer, folding the outcome of every real request through the single `TMDB.Client.get/3` funnel; `TMDB.ProbeJob` keeps the value current while down with one `GET /configuration` every five minutes (the cheapest call, and the one that already exists to prove the key). `ReleaseTracking.Refresher` consults the value at its tick and again per item, so one transport failure ends that cycle's TMDB traffic instead of repeating it for every tracked title, and it runs the deferred cycle when the recovery broadcast arrives. `TmdbArtwork.ensure/2` serves what is on disk while TMDB is down. Spec: `docs/superpowers/specs/2026-09-17-availability-design.md`. Campaign: `campaigns/recurring-traffic-audit.md`.

**Tech Stack:** Elixir/Phoenix, Oban 2.24 (Lite engine; `testing: :inline` in tests), Req + `Req.Test` stubs (`:tmdb`, `:tmdb_images`), Boundary, ExUnit with `MediaCentaur.DataCase` / `MediaCentaur.Case`.

---

## Decisions this plan takes

Two calls the spec leaves implicit, both stated here so a reviewer can
reject them cheaply:

1. **A rejected TMDB key opens `:tmdb`.** The spec's evidence table lists
   "transport error, 5xx, 429" for `:tmdb` and does not mention 401/403.
   Prowlarr's writer already treats 401/403 as `:rejected` on the spec's
   own reasoning — *misconfigured is as useless as dead for held work* —
   and without it a rejected key is re-hammered by every refresh cycle
   and every artwork warm. `:tmdb` takes the same treatment.
2. **The image CDN does not write `:tmdb`.** `image.tmdb.org` and
   `api.themoviedb.org` are different hosts; a CDN failure is no evidence
   about the API, and holding metadata refreshes on it would be the wrong
   blame — the same rule step 1 wrote for the hand-off probe
   ("inconclusive moves nothing"). Only `TMDB.Client` writes the value.
   Image downloads are still held, because they ride the detail fetch
   that the gate stops.

A third thing is **deliberately not in this step**: TMDB has no
`:subsystem` incident of its own (`TMDB.IncidentContext` implements
`vitals/0` only), so a sustained TMDB outage still does not raise a
condition on the Status board the way a Prowlarr one now does. The
spec puts TMDB's user-visible surface on the Connections tile in step 5.
Noted in the campaign as an open item rather than widened into here.

## Rules that apply to every task

- **Never run `mix` directly.** Every mix invocation is `~/scripts/agents/agent-mix <task>`. A bare `mix` takes the running dev server down.
- **One editing agent at a time in this checkout.** Reviews are read-only and may run in parallel.
- **Test-first.** Write the test, run it red for the right reason, implement, run green.
- **Sandbox rules.** Any test calling `IntegrationAvailability.report/3` writes `:persistent_term` and must be sync (`MediaCentaur.Case, async: false`, or `DataCase`). Pure tests stay `async: true`.
- **Setting a down integration in a test** is `IntegrationAvailability.report(:tmdb, {:down, :unreachable})` — the store directly, not `TMDB.Availability`, so no probe job is enqueued into the inline Oban.
- **Oban runs inline in tests.** A test that drives a down transition *through the writer* runs `TMDB.ProbeJob` immediately against the `:tmdb` stub, which must then answer `GET /3/configuration`.
- **TMDB stubs** are `MediaCentaur.TmdbStubs` (`test/support/tmdb_stubs.ex`) over `Req.Test` — never a mocking library.
- **A new module plus a new `exports:` entry needs `~/scripts/agents/agent-mix compile --force` once** (memory `reference-boundary-stale-export-manifest`).
- **Placeholders only** in tests and docs: "Sample Show", "Sample Movie".
- **Zero warnings.** `--warnings-as-errors` is on.
- The shell is fish: quote glob-like arguments.
- Commit after each task with the trailer `Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF`. Never a Co-Authored-By line.

## File map

| File | Responsibility |
|---|---|
| Modify `lib/media_centaur/integration_availability/status.ex` | `:rate_limited` joins the reason vocabulary |
| Modify `lib/media_centaur/acquisition/view_models/search_outage.ex` | A clause for it, so the dispatch stays total |
| Create `lib/media_centaur/tmdb/availability.ex` | The one writer for `:tmdb`: folds request outcomes, enqueues the probe on a down transition |
| Modify `lib/media_centaur/tmdb/client.ex` | `get/3` reports every outcome; a cache hit reports nothing |
| Create `lib/media_centaur/tmdb/probe_job.ex` | Oban worker: `GET /configuration` every 5 min while down, completes on up |
| Modify `lib/media_centaur/tmdb.ex` | Boundary dep + exports |
| Modify `lib/media_centaur/release_tracking/refresher.ex` | Holds at the tick and per item; runs the deferred cycle on recovery |
| Modify `lib/media_centaur/release_tracking.ex` | Boundary dep |
| Modify `lib/media_centaur/tmdb_artwork.ex` | `ensure/2` serves what is on disk while TMDB is down |
| Wiki `../media-centaur.wiki/Troubleshooting.md` | What the app does while TMDB is down |
| `campaigns/recurring-traffic-audit.md` | Status, decisions, next steps after step 3 |

---

### Task 1: `:rate_limited` joins the reason vocabulary

TMDB answers 429 when its rate limit is hit. The existing reasons —
`:unreachable`, `:rejected`, `:blind`, `:client_unavailable` — would file
that under "unreachable", which is wrong in the one way that matters to
the person reading it: the server is fine and answering.

**Files:**
- Modify: `lib/media_centaur/integration_availability/status.ex`
- Modify: `lib/media_centaur/acquisition/view_models/search_outage.ex`
- Test: `test/media_centaur/integration_availability/status_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/integration_availability/status_test.exs`, in the `fold/4` describe:

```elixir
    test "a rate-limited integration is down for a reason of its own" do
      status = Status.initial(:tmdb)

      assert {:changed, %Status{state: {:down, @t1, :rate_limited}}} =
               Status.fold(status, {:down, :rate_limited}, @t1, [])
    end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/integration_availability/status_test.exs`
Expected: it compiles and passes — `fold/4` does not match on the reason atom. **This is the one task whose test cannot go red**, because the value is already reason-agnostic; the type is the thing being widened. Treat the test as the documentation of the new reason and check the Dialyzer contract instead: with `:rate_limited` missing from `@type reason`, `~/scripts/agents/agent-mix dialyzer` (or the `@spec` on `TMDB.Availability.observe_request/1` in Task 2) is what rejects it. Write the test, see it green, and let Task 2's compile be the real gate.

- [ ] **Step 3: Widen the type**

In `lib/media_centaur/integration_availability/status.ex`:

```elixir
  @type reason :: :unreachable | :rejected | :rate_limited | :blind | :client_unavailable
```

and in the moduledoc's reason list, after `:rejected`:

```
  `:rate_limited` (429 — the integration is answering and refusing to do
  more work for now),
```

In `lib/media_centaur/acquisition/view_models/search_outage.ex`, keep the dispatch total:

```elixir
  # Prowlarr does not rate-limit us — its indexers' back-off is `:blind`,
  # and `:rate_limited` is TMDB's.
  defp line(:rate_limited), do: nil
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/integration_availability/ test/media_centaur/acquisition/view_models/search_outage_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/integration_availability/status.ex lib/media_centaur/acquisition/view_models/search_outage.ex test/media_centaur/integration_availability/status_test.exs
git commit -m "feat(availability): a rate-limited integration has its own reason

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 2: `TMDB.Availability` — the one writer

**Files:**
- Create: `lib/media_centaur/tmdb/availability.ex`
- Modify: `lib/media_centaur/tmdb.ex` (Boundary dep + export)
- Test: `test/media_centaur/tmdb/availability_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/media_centaur/tmdb/availability_test.exs`:

```elixir
defmodule MediaCentaur.TMDB.AvailabilityTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.Availability

  describe "observe_request/1" do
    test "an answered request is evidence TMDB is up" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert {:changed, :up} = Availability.observe_request({:ok, :fetched})
      assert IntegrationAvailability.up?(:tmdb)
    end

    test "an answer served from the cache asked nobody, so it is no evidence" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert :unchanged = Availability.observe_request({:ok, :hit})
      refute IntegrationAvailability.up?(:tmdb)
    end

    test "a transport error, a 5xx and a 429 each open TMDB, with their own reason" do
      assert {:changed, {:down, _since, :unreachable}} =
               Availability.observe_request({:error, %Req.TransportError{reason: :timeout}})

      IntegrationAvailability.report(:tmdb, :up)

      assert {:changed, {:down, _since, :unreachable}} =
               Availability.observe_request({:error, {:http_error, 503, ""}})

      IntegrationAvailability.report(:tmdb, :up)

      assert {:changed, {:down, _since, :rate_limited}} =
               Availability.observe_request({:error, {:http_error, 429, ""}})
    end

    test "a rejected key is as useless as a dead server, and says which" do
      assert {:changed, {:down, _since, :rejected}} =
               Availability.observe_request({:error, {:http_error, 401, ""}})
    end

    test "any other 4xx is about the request, not the server" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert :unchanged = Availability.observe_request({:error, {:http_error, 404, ""}})
      refute IntegrationAvailability.up?(:tmdb)
    end
  end
end
```

Note the last assertion: a 404 means TMDB answered, but it is *not* used
to close an outage either — a 404 for an unknown id can be served while
the rest of the API is sick, and the probe is what closes the value.
`:unchanged` with the status still down is the expected shape.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/availability_test.exs`
Expected: FAIL — `module MediaCentaur.TMDB.Availability is not available`.

- [ ] **Step 3: Write the module**

Create `lib/media_centaur/tmdb/availability.ex`:

```elixir
defmodule MediaCentaur.TMDB.Availability do
  @moduledoc """
  The one writer of `:tmdb` availability
  (`MediaCentaur.IntegrationAvailability`).

  `MediaCentaur.TMDB.Client` calls `observe_request/1` after every
  request it makes, and `MediaCentaur.TMDB.ProbeJob` keeps the value
  current with a `GET /configuration` every five minutes while down.

  Two rules keep the value honest:

    * **A cache hit is not evidence.** The response cache answers without
      asking TMDB anything (`HttpClient.Cache.outcome/1` grades it
      `:hit`), so it can neither open nor close the value.
    * **The image CDN never writes here.** `image.tmdb.org` is a
      different host from `api.themoviedb.org`; a failed artwork download
      says nothing about the API, and holding every metadata refresh on
      it would be the wrong blame. Artwork is held anyway, because the
      detail fetch it follows is.

  A 4xx that is not 401/403 is about the request — an unknown id — so it
  neither opens the value nor closes it: TMDB answering one 404 is no
  proof the outage is over, and the probe is what says so.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.TMDB.ProbeJob

  @type outcome :: {:ok, atom()} | {:error, term()}

  @doc "Folds one request outcome into `:tmdb`."
  @spec observe_request(outcome()) :: :unchanged | {:changed, Status.state()}
  def observe_request({:ok, :hit}), do: :unchanged
  def observe_request({:ok, _network}), do: report(:up)

  def observe_request({:error, {:http_error, status, _body}}) when status in [401, 403],
    do: report({:down, :rejected})

  def observe_request({:error, {:http_error, 429, _body}}), do: report({:down, :rate_limited})

  def observe_request({:error, {:http_error, status, _body}}) when status >= 500,
    do: report({:down, :unreachable})

  def observe_request({:error, {:http_error, _status, _body}}), do: :unchanged
  def observe_request({:error, _transport}), do: report({:down, :unreachable})

  defp report(observation) do
    case IntegrationAvailability.report(:tmdb, observation) do
      {:changed, {:down, _since, _reason}} = changed ->
        enqueue_probe()
        changed

      other ->
        other
    end
  end

  defp enqueue_probe do
    if Capabilities.tmdb_ready?() do
      job = ProbeJob.new(%{}, schedule_in: ProbeJob.cadence_seconds())

      # The enqueue sits on the request path: a database hiccup must cost
      # the probe, never the request that observed the outage.
      case Oban.insert(job) do
        {:ok, _job} ->
          :ok

        {:error, reason} ->
          Log.warning(:tmdb, "probe not enqueued for tmdb — #{inspect(reason)}",
            mc_incident: :skip
          )
      end
    end

    :ok
  end
end
```

In `lib/media_centaur/tmdb.ex`, add the Boundary dep and the exports:

```elixir
  use Boundary,
    deps: [
      MediaCentaur.Capabilities,
      MediaCentaur.ErrorReports,
      MediaCentaur.HttpClient,
      MediaCentaur.IntegrationAvailability
    ],
    exports: [
      Availability,
      Client,
      ...
      ProbeJob,
      ...
    ]
```

(Keep the existing export list; add `Availability` and `ProbeJob` in
alphabetical position. `Capabilities` may already be a dep — check before
adding it twice.)

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/scripts/agents/agent-mix compile --force`, then
`~/scripts/agents/agent-mix test test/media_centaur/tmdb/availability_test.exs`
Expected: FAIL still, on `MediaCentaur.TMDB.ProbeJob` being undefined — write Task 3 first if you want a green run here, or land both together. Prefer landing Task 3's module in this same commit if the compile blocks; the two are one seam.

- [ ] **Step 5: Commit** (with Task 3, if they landed together)

---

### Task 3: `TMDB.ProbeJob` — one cheap call every five minutes while down

**Files:**
- Create: `lib/media_centaur/tmdb/probe_job.ex`
- Test: `test/media_centaur/tmdb/probe_job_test.exs`

- [ ] **Step 1: Write the failing test**

Create `test/media_centaur/tmdb/probe_job_test.exs`:

```elixir
defmodule MediaCentaur.TMDB.ProbeJobTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.ProbeJob
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  test "a probe that answers marks TMDB up and the job completes" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
    Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, %{"images" => %{}}) end)

    assert :ok = perform_probe()
    assert IntegrationAvailability.up?(:tmdb)
  end

  test "a probe that fails snoozes at the cadence and leaves TMDB down" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
    Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:snooze, 300} = perform_probe()
    refute IntegrationAvailability.up?(:tmdb)
  end

  test "a probe that raises snoozes rather than burning an attempt" do
    {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})
    Req.Test.stub(:tmdb, fn _conn -> raise "boom" end)

    assert {:snooze, 300} = perform_probe()
  end

  defp perform_probe do
    Oban.Testing.perform_job(ProbeJob, %{}, repo: MediaCentaur.Repo, engine: Oban.Engines.Lite)
  end
end
```

Check `TmdbStubs.setup_tmdb_client/0`'s arity and whether it needs
`self()` — read `test/support/tmdb_stubs.ex` and call it the way the other
TMDB tests do. A raise inside a `Req.Test` stub surfaces to the caller as
an error tuple or an exception depending on the adapter; if the third
test's expectation does not hold, assert the behaviour the run actually
shows (a snooze either way) rather than forcing the shape.

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/probe_job_test.exs`
Expected: FAIL — `MediaCentaur.TMDB.ProbeJob is not available`.

- [ ] **Step 3: Write the worker**

Create `lib/media_centaur/tmdb/probe_job.ex`:

```elixir
defmodule MediaCentaur.TMDB.ProbeJob do
  @moduledoc """
  Keeps a down TMDB's availability fresh with one cheap request.

  Enqueued by `MediaCentaur.TMDB.Availability` on a transition to down.
  Each run asks `Client.configuration/1` — static image-CDN metadata,
  always reloaded past the cache, the same call the "Test connection"
  button makes — which reports through `Availability.observe_request/1`
  like any other request. It then snoozes at the cadence while still
  down, and completes on up. A run also completes when TMDB is no longer
  configured: the probe cannot answer without a key, and a job that only
  ever snoozes would outlive the integration.

  TMDB is metered, so the probe is one request every five minutes — the
  one metered request this design spends to avoid spending many. While
  up nothing probes: real requests are the evidence.

  On the `:maintenance` queue, `unique` so two never queue at once.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: [:available, :scheduled, :executing, :retryable]]

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.Client

  @cadence_seconds 300

  @doc "Seconds between probes while down; also the wait of work this holds."
  @spec cadence_seconds() :: pos_integer()
  def cadence_seconds, do: @cadence_seconds

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Capabilities.tmdb_ready?() do
      probe()
    else
      :ok
    end
  end

  # A probe that breaks must not burn an attempt: three raises would
  # discard the job and leave a down integration with nothing watching
  # it, so held work would stall with no path back. Snooze instead.
  defp probe do
    _answer = Client.configuration()

    if IntegrationAvailability.up?(:tmdb), do: :ok, else: {:snooze, @cadence_seconds}
  rescue
    error ->
      Log.warning(:tmdb, "probe failed for tmdb — #{Exception.message(error)}", mc_incident: :skip)
      {:snooze, @cadence_seconds}
  catch
    :exit, reason ->
      Log.warning(:tmdb, "probe exited for tmdb — #{inspect(reason)}", mc_incident: :skip)
      {:snooze, @cadence_seconds}
  end
end
```

- [ ] **Step 4: Run both test files**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb/availability.ex lib/media_centaur/tmdb/probe_job.ex lib/media_centaur/tmdb.ex test/media_centaur/tmdb/
git commit -m "feat(tmdb): TMDB writes its own availability, and a probe keeps it fresh

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 4: Every TMDB request reports its outcome

**Files:**
- Modify: `lib/media_centaur/tmdb/client.ex`
- Test: `test/media_centaur/tmdb/client_test.exs` (or the existing TMDB client test file — grep for it first)

- [ ] **Step 1: Write the failing test**

In the TMDB client's test file, add:

```elixir
  describe "availability" do
    test "a failed fetch opens :tmdb and a later answered one closes it" do
      Req.Test.stub(:tmdb, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _reason} = Client.get_movie(550)
      refute IntegrationAvailability.up?(:tmdb)

      Req.Test.stub(:tmdb, fn conn -> Req.Test.json(conn, %{"id" => 550}) end)

      assert {:ok, _body} = Client.get_movie(550)
      assert IntegrationAvailability.up?(:tmdb)
    end
  end
```

The file must be sync (`DataCase` or `MediaCentaur.Case, async: false`) —
this writes `:persistent_term` and, through the writer, inserts an Oban
job. Follow whatever that file already uses; convert it if it is async
and say so in the commit.

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — `:tmdb` stays up after the transport error.

- [ ] **Step 3: Report from the one funnel**

In `lib/media_centaur/tmdb/client.ex`, add the alias and report in `get/3`:

```elixir
  alias MediaCentaur.TMDB.Availability
```

```elixir
  defp get(opts, request, subject) do
    {client, opts} = Keyword.pop_lazy(opts, :client, &default_client/0)

    case Req.get(client, request ++ opts) do
      {:ok, %{status: 200, body: body} = response} ->
        outcome = Cache.outcome(response)
        Availability.observe_request({:ok, outcome})
        Log.info(:tmdb, log_line(subject, outcome))
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Availability.observe_request({:error, {:http_error, status, body}})
        {:error, {:http_error, status, body}}

      {:error, reason} ->
        Availability.observe_request({:error, reason})
        {:error, reason}
    end
  end
```

Add to the moduledoc, after the "The console line" section:

```
  ## Availability

  Every request's outcome is folded into `MediaCentaur.TMDB.Availability`
  — the `:tmdb` half of `MediaCentaur.IntegrationAvailability` — so the
  release-tracking refresh cycle and the artwork warm can ask whether
  TMDB can answer before they spend a request on finding out. An answer
  served from the response cache reports nothing: it asked nobody.
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb/`
Expected: PASS. Then run the wider TMDB-touching suites — `~/scripts/agents/agent-mix test test/media_centaur/release_tracking/ test/media_centaur/pipeline/` — because every stubbed TMDB failure in the suite now writes the value, and a sync test that leaves `:tmdb` down would be caught by the sandbox, not by you.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb/client.ex test/media_centaur/tmdb/
git commit -m "feat(tmdb): every request's outcome writes TMDB's availability

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 5: The refresh cycle holds, and resumes on recovery

Measured 2026-09-17: the cycle fetches every tracked item every 6 hours
with `reload: true`, 1–2 season calls per TV item, concurrency 4, and a
per-item error is skipped with the cadence unchanged. During a TMDB
outage that is the whole library's worth of doomed requests, twice a day.

**Files:**
- Modify: `lib/media_centaur/release_tracking/refresher.ex`
- Modify: `lib/media_centaur/release_tracking.ex` (Boundary dep)
- Test: `test/media_centaur/release_tracking/refresher_test.exs`

- [ ] **Step 1: Write the failing test**

Add to `test/media_centaur/release_tracking/refresher_test.exs`:

```elixir
  describe "held work — a known-down TMDB is not asked" do
    test "the cycle is skipped and no TMDB request is made" do
      test_pid = self()
      Req.Test.stub(:tmdb, fn conn -> send(test_pid, {:tmdb_called, conn.request_path}) && Req.Test.json(conn, %{}) end)

      create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"})
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      send(Process.whereis(Refresher), :refresh)
      _synced = Refresher.__tick_for_test__(fn -> :ok end)

      refute_received {:tmdb_called, _path}
    end

    test "recovery runs the cycle that was held" do
      ...
    end
  end
```

Read the file's existing tests first: it already drives the Refresher
through `__tick_for_test__/1` and has a `Refresher` under test — reuse
its setup verbatim rather than the sketch above, and drive the tick the
way it already does. The two behaviours to pin are: **(a)** with `:tmdb`
down, a `:refresh` tick makes no TMDB request and re-arms at the probe
cadence; **(b)** an `{:integration_availability_changed, :tmdb, :up}`
message makes the Refresher run the cycle it deferred, and a second such
message with nothing deferred runs nothing.

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — the cycle ran and TMDB was called.

- [ ] **Step 3: Hold at the tick, per item, and on recovery**

In `lib/media_centaur/release_tracking.ex`, add to the Boundary `deps:`:

```elixir
      MediaCentaur.IntegrationAvailability,
```

In `lib/media_centaur/release_tracking/refresher.ex`:

```elixir
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.ProbeJob
```

`init/1` subscribes and seeds the flag:

```elixir
    IntegrationAvailability.subscribe()

    {:ok, %{deferred_refresh?: false}}
```

The refresh tick consults the value:

```elixir
  @impl true
  def handle_info(:refresh, state) do
    if IntegrationAvailability.available?(:tmdb) do
      held? = tick("refresh cycle", &do_refresh_all/0) == :held
      schedule_refresh(if held?, do: hold_interval_ms(), else: refresh_interval_ms())
      {:noreply, %{state | deferred_refresh?: held?}}
    else
      Log.info(:acquisition, "release tracking: refresh cycle held — TMDB is unavailable")
      schedule_refresh(hold_interval_ms())
      {:noreply, %{state | deferred_refresh?: true}}
    end
  end

  # TMDB answered again: run the cycle the outage held, rather than
  # waiting out the rest of the interval. Nothing deferred, nothing to do
  # — every other integration and every down transition falls through.
  def handle_info({:integration_availability_changed, :tmdb, :up}, %{deferred_refresh?: true} = state) do
    tick("deferred refresh cycle", &do_refresh_all/0)
    schedule_refresh(refresh_interval_ms())
    {:noreply, %{state | deferred_refresh?: false}}
  end

  def handle_info({:integration_availability_changed, _integration, _state_change}, state),
    do: {:noreply, state}
```

`tick/2` returns the function's value so the caller can see a held cycle:

```elixir
  defp tick(name, fun) do
    fun.()
  rescue
    ...
```

(Delete the trailing `:ok` that currently discards it. `do_sweep/0`
already ends in `:ok`, and the two tests that assert on `tick/2` assert
`:error` for a raise and an exit — unchanged.)

Mid-cycle, each item checks before it fetches, and the cycle reports
whether anything was held:

```elixir
  defp do_refresh_all do
    Log.info(:acquisition, "release tracking: starting refresh cycle")

    items = ReleaseTracking.list_all_items()

    fetched = ... # unchanged

    held = Enum.count(fetched, &match?({:ok, {:held, _item}}, &1))

    successful =
      Enum.flat_map(fetched, fn
        {:ok, {:ok, item, response, calendar}} ->
          commit_refresh(item, response, calendar)
          [{item, response}]

        {:ok, {:held, _item}} ->
          []

        {:ok, {:error, item, reason}} ->
          Log.info(:acquisition, "refresh failed for #{item.name}: #{inspect(reason)}")
          []

        {:exit, reason} ->
          Log.info(:acquisition, "refresh task crashed: #{inspect(reason)}")
          []
      end)

    bulk_download_images(successful)

    ... # broadcast unchanged

    if held > 0 do
      # One line for the whole cycle, not one per title: TMDB went down
      # mid-cycle and every remaining item would have said the same.
      Log.info(
        :acquisition,
        "release tracking: refresh cycle incomplete — TMDB went unavailable (#{held} of #{length(items)} items held)"
      )

      :held
    else
      Log.info(:acquisition, "release tracking: refresh complete (#{length(items)} items)")
      :ok
    end
  end
```

and each fetch clause starts with the check — put it in one place by
wrapping, not by repeating it in all three:

```elixir
  defp fetch_for_item(item) do
    if IntegrationAvailability.up?(:tmdb), do: fetch_item_detail(item), else: {:held, item}
  end

  defp fetch_item_detail(%{media_type: :tv_series} = item) do
    ...  # today's fetch_for_item/1 clauses, renamed
  end
```

and the hold interval:

```elixir
  defp hold_interval_ms, do: ProbeJob.cadence_seconds() * 1_000
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/release_tracking/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/release_tracking/refresher.ex lib/media_centaur/release_tracking.ex test/media_centaur/release_tracking/refresher_test.exs
git commit -m "feat(release-tracking): the refresh cycle is held while TMDB is down

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 6: The artwork warm serves what is on disk

`TmdbArtwork.ensure/2` runs per fresh mount per identity, and for an
identity TMDB has no artwork for there is no negative cache — so it
re-fetches on every mount. While TMDB is down every one of those is a
doomed request on the render path.

**Files:**
- Modify: `lib/media_centaur/tmdb_artwork.ex`
- Test: `test/media_centaur/tmdb_artwork_test.exs`

- [ ] **Step 1: Write the failing test**

Add to the artwork test file (read it first; it has fixtures for the
cache directory):

```elixir
  describe "held work — a known-down TMDB is not asked" do
    test "ensure/2 answers from disk and fetches nothing" do
      test_pid = self()
      Req.Test.stub(:tmdb, fn conn -> send(test_pid, {:tmdb_called, conn.request_path}) && Req.Test.json(conn, %{}) end)

      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert %{poster_url: nil, backdrop_url: nil, logo_url: nil} =
               TmdbArtwork.ensure(:movie, 246_813)

      refute_received {:tmdb_called, _path}
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: FAIL — the detail fetch happened.

- [ ] **Step 3: Gate the fetch**

In `lib/media_centaur/tmdb_artwork.ex`, add to the Boundary `deps:`:

```elixir
    deps: [
      MediaCentaur.IntegrationAvailability,
      MediaCentaur.Library,
      MediaCentaur.Retention,
      MediaCentaur.TMDB
    ],
```

alias it, and gate the fetch inside `ensure/2`'s `with`:

```elixir
  def ensure(type, tmdb_id) do
    with id when not is_nil(id) <- normalize_id(tmdb_id),
         type = normalize_type(type),
         %{poster_url: p, backdrop_url: b, logo_url: l}
         when is_nil(p) or is_nil(b) or is_nil(l) <- urls(type, id) do
      # Held: whatever is already on disk is the answer. A warm that
      # cannot reach TMDB has nothing to add, and this runs on the render
      # path of every fresh mount.
      if IntegrationAvailability.up?(:tmdb) do
        fetch_missing(type, id)
        touch(type, id)
      end

      urls(type, id)
    else
      nil -> %{poster_url: nil, backdrop_url: nil, logo_url: nil}
      %{} = resolved -> resolved
    end
  end
```

Add a sentence to the moduledoc's Lifecycle section:

```
  While TMDB is unavailable (`MediaCentaur.IntegrationAvailability`)
  `ensure/2` answers from what is already on disk and fetches nothing —
  it runs on the render path of every fresh mount, and a warm that cannot
  reach TMDB has nothing to add.
```

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/tmdb_artwork_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/tmdb_artwork.ex test/media_centaur/tmdb_artwork_test.exs
git commit -m "feat(tmdb): the artwork warm serves what is on disk while TMDB is down

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

### Task 7: Docs, wiki, campaign, precommit, and the measurement the spec asks for

**Files:**
- Modify: `../media-centaur.wiki/Troubleshooting.md`
- Modify: `campaigns/recurring-traffic-audit.md`

- [ ] **Step 1: Wiki**

In the **TMDB isn't matching / metadata is wrong** section of
`../media-centaur.wiki/Troubleshooting.md`, add:

```markdown
- **Metadata and artwork stop updating** — when TMDB stops answering, rejects your API key, or rate-limits us, the app stops asking: the periodic refresh of tracked titles is skipped and artwork is served from what has already been downloaded. It re-checks every five minutes, and the refresh it skipped runs as soon as TMDB answers again. Your library and its existing artwork are unaffected; only new metadata waits.
```

Commit in the wiki repo:

```bash
cd ~/src/media-centaur/media-centaur.wiki
git add -A
git commit -m "wiki: what the app does while TMDB is down"
git push
```

- [ ] **Step 2: Measure a simulated outage** (spec: "Measure a simulated TMDB outage here, as verification")

Against the dev node, with `~/scripts/agents/mc-eval` and a `try/after`
so the restore always runs (memory `reference-mc-eval-reload-purge`):
report `:tmdb` down, read `HttpClient.Stats.snapshot().upstreams` for the
`tmdb` and `tmdb_images` rows, wait out one refresh window or drive one
tick, read them again, then report up and confirm the deferred cycle
runs. Record the before/after request counts in the campaign's Evidence
section. The completion criterion is the campaign's: **requests/hour per
server during a simulated outage are below the healthy-day rate, not
above it.**

- [ ] **Step 3: Campaign**

In `campaigns/recurring-traffic-audit.md`:

- Status: steps 1–3 landed; step 4 (GitHub and relays — confirm only) is next.
- A "What step 3 added" paragraph in the same shape as step 2's.
- Inventory: the *Tracking refresh*, *Tracking image backfill* and
  *Artwork warm on mount* rows get their post-step-3 gate.
- Decisions: the two this plan takes (a rejected key opens `:tmdb`; the
  image CDN does not write it), and the open item — TMDB has no
  `:subsystem` incident, so a sustained TMDB outage is not on the Status
  board until step 5's Connections tile.
- Evidence: the measured outage numbers from Step 2.

- [ ] **Step 4: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: PASS, zero warnings.

- [ ] **Step 5: Commit**

```bash
git add campaigns/recurring-traffic-audit.md
git commit -m "docs: availability step 3 landed — campaign status and the outage measurement

Claude-Session: https://claude.ai/code/session_01DartCM8viJppYVfPnQFUhF"
```

---

## Verification after the last task

- `~/scripts/agents/agent-mix precommit` green, zero warnings.
- `grep -rn 'Client.get_movie\|Client.get_tv\|Client.get_season\|Client.get_collection' lib` — every caller either runs behind one of the new gates (refresher, artwork warm) or is user-initiated (search, the review flow, a manual re-identify), which is allowed to spend a request on finding out.
- On the dev node, with `:tmdb` forced down inside a `try/after`: `Refresher` makes no TMDB request on a tick, `TmdbArtwork.ensure/2` answers from disk, and reporting up runs the deferred cycle.

## Self-review against the spec

- **Evidence and probes, `:tmdb` row** — Tasks 2–4 (opens on transport error, 5xx, 429 — plus 401/403 by this plan's decision 1; probe is `GET /configuration` at 5 min; closes on any answered request).
- **Held work, `Refresher` row** — Task 5, both halves (tick-entry gate and the per-item check so one transport failure ends the cycle's traffic), image backfill riding the same gate because it only receives successfully fetched items.
- **Held work, `TmdbArtwork.ensure/2` row** — Task 6.
- **Recovery, `ReleaseTracking.Refresher`** — Task 5's subscriber.
- **Scope and cost, step 3** — "`:tmdb` writer, `TMDB.ProbeJob`, `Refresher` and `TmdbArtwork` gates. Wiki: TMDB down entry. Measure a simulated TMDB outage here." All covered; the measurement is Task 7 Step 2.
- **Not in this step:** GitHub and relays (step 4), queue-monitor log transitions and the Connections tile's *down since* (step 5), and TMDB's refresh *policy* — how often it re-reads a healthy TMDB — which belongs to `project-tmdb-caching-refresh-policy`, not here.
