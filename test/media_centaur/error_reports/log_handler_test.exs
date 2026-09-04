defmodule MediaCentaur.ErrorReports.LogHandlerTest do
  # The durable handler casts into an isolated Buckets instance — Console.Buffer
  # is never in the path, which is the whole point: durable capture is a peer of
  # the volatile console, not downstream of it.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports.{Buckets, Fingerprint, LogHandler, Store}

  setup do
    start_supervised!({Buckets, name: :lh_buckets})
    :ok
  end

  defp uniq do
    System.unique_integer([:positive])
    |> Integer.to_string()
    |> String.to_charlist()
    |> Enum.map_join(fn digit -> <<digit - ?0 + ?a>> end)
  end

  defp event(level, message, meta \\ %{component: :tmdb}) do
    %{level: level, msg: {:string, message}, meta: meta}
  end

  defp config, do: %{config: %{buckets: :lh_buckets}}

  defp fingerprint_of(message), do: Fingerprint.fingerprint(:tmdb, message).key

  test "an error event is captured durably without touching Console.Buffer" do
    message = "log handler error #{uniq()}"
    fingerprint = fingerprint_of(message)

    assert LogHandler.log(event(:error, message), config()) == :ok

    # get_bucket is a GenServer call, so it can only return after the prior
    # ingest cast was processed — the barrier that makes the durable write
    # (synchronous inside the cast) observable here.
    assert Buckets.get_bucket(:lh_buckets, fingerprint)
    assert %{count: 1, severity: :error, origin: :log} = Store.get_incident_by_fingerprint(fingerprint)
  end

  test "a warning event is captured as warning severity" do
    message = "log handler warning #{uniq()}"
    fingerprint = fingerprint_of(message)

    LogHandler.log(event(:warning, message), config())

    assert Buckets.get_bucket(:lh_buckets, fingerprint)
    assert %{severity: :warning} = Store.get_incident_by_fingerprint(fingerprint)
  end

  test "info and debug events are ignored" do
    info_message = "log handler info #{uniq()}"
    debug_message = "log handler debug #{uniq()}"

    LogHandler.log(event(:info, info_message), config())
    LogHandler.log(event(:debug, debug_message), config())

    assert Store.get_incident_by_fingerprint(fingerprint_of(info_message)) == nil
    assert Store.get_incident_by_fingerprint(fingerprint_of(debug_message)) == nil
  end

  test "the Buffer's own self-logs are not re-captured" do
    message = "log handler buffer self log #{uniq()}"

    LogHandler.log(event(:error, message, %{component: :tmdb, mc_log_source: :buffer}), config())

    assert Store.get_incident_by_fingerprint(fingerprint_of(message)) == nil
  end

  test "events marked mc_incident: :skip are not captured as :log incidents (ADR-054)" do
    # An assessor-owned connectivity log: it still reaches the volatile console,
    # but a subsystem `assess/0` owns the incident, so it must NOT mint a
    # duplicate `:log` incident here.
    skipped = "qbittorrent sync_maindata error #{uniq()}"
    sentinel = "ordinary acquisition warning #{uniq()}"

    LogHandler.log(event(:warning, skipped, %{component: :acquisition, mc_incident: :skip}), config())
    LogHandler.log(event(:warning, sentinel, %{component: :acquisition}), config())

    # Barrier: get_bucket is a GenServer call, so it only returns after every
    # prior ingest cast has been processed — including the suppressed one, had it
    # (wrongly) enqueued a cast. The sentinel proves the path is live.
    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:acquisition, sentinel).key)

    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:acquisition, skipped).key) ==
             nil
  end

  test "malformed events never raise out of the handler" do
    assert LogHandler.log(%{level: :error, msg: {:weird, make_ref()}, meta: %{}}, config()) == :ok
  end

  defp crash_event(level, message, crash_reason) do
    %{
      level: level,
      msg: {:string, message},
      meta: %{component: :system, crash_reason: crash_reason}
    }
  end

  test "Bandit transport timeouts are not minted as :log incidents (client disconnect)" do
    # A read/write socket timeout means the client stopped responding — a
    # transport-layer event, not an application fault. It still reaches the
    # console, but must not mint a durable `:log` incident.
    skipped = "Unrecoverable error: timeout #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"

    LogHandler.log(
      crash_event(:error, skipped, {%Bandit.TransportError{error: :timeout, message: skipped}, []}),
      config()
    )

    LogHandler.log(event(:error, sentinel, %{component: :system}), config())

    # Barrier: the sentinel's GenServer call returns only after every prior
    # ingest cast is processed — proving the path is live and the skip silent.
    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, skipped).key) == nil
  end

  test "Bandit client closures are not minted as :log incidents" do
    skipped = "closed #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"

    LogHandler.log(
      crash_event(:error, skipped, {%Bandit.TransportError{error: :closed, message: skipped}, []}),
      config()
    )

    LogHandler.log(event(:error, sentinel, %{component: :system}), config())

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, skipped).key) == nil
  end

  test "Bandit HTTP read timeouts are not minted as :log incidents (client stalled)" do
    # Bandit raises %Bandit.HTTPError{plug_status: :request_timeout} when the
    # client opens a connection and then stops sending — the HTTP-layer twin of
    # the TransportError :timeout above. Same family, same exclusion.
    skipped = "** (Bandit.HTTPError) Read timeout #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"

    LogHandler.log(
      crash_event(
        :error,
        skipped,
        {%Bandit.HTTPError{message: "Read timeout", plug_status: :request_timeout}, []}
      ),
      config()
    )

    LogHandler.log(event(:error, sentinel, %{component: :system}), config())

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, skipped).key) == nil
  end

  test "Req's own retry log lines are not minted as :log incidents (transient + auto-retried)" do
    # Req logs every retry attempt from `Req.Steps.log_retry/5` — the exception
    # it caught plus a "will retry in N, attempts left" line. A retry-in-progress
    # is transient by definition: if it ultimately fails, the *caller* logs a
    # terminal error (which mints). These intermediate lines still reach the
    # console, but must not mint durable `:log` incidents that then sit "open"
    # until the next deploy.
    exception = "** (Req.HTTPError) http2 error: :pool_not_available #{uniq()}"
    retry = "retry: got exception, will retry in <N>, 3 attempts left #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"

    retry_meta = %{component: :system, mfa: {Req.Steps, :log_retry, 5}}
    LogHandler.log(event(:warning, exception, retry_meta), config())
    LogHandler.log(event(:warning, retry, retry_meta), config())
    LogHandler.log(event(:warning, sentinel, %{component: :system}), config())

    # Barrier: the sentinel's GenServer call returns only after every prior
    # ingest cast is processed — proving the path is live and the skips silent.
    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, exception).key) == nil
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, retry).key) == nil
  end

  test "a non-timeout Bandit HTTP error still mints" do
    minted = "** (Bandit.HTTPError) Header read HTTP error #{uniq()}"

    LogHandler.log(
      crash_event(
        :error,
        minted,
        {%Bandit.HTTPError{message: "Header read HTTP error", plug_status: :bad_request}, []}
      ),
      config()
    )

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, minted).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, minted).key)
  end

  test "an unusual transport reason still mints — we don't blind ourselves" do
    minted = "Unrecoverable error: emfile #{uniq()}"

    LogHandler.log(
      crash_event(:error, minted, {%Bandit.TransportError{error: :emfile, message: minted}, []}),
      config()
    )

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, minted).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, minted).key)
  end

  test "a stale-closure BadFunctionError from a hot-reload purge is not minted (dev-only artifact)" do
    # Broadway/GenStage crash pattern: a process holds a closure captured before
    # `Phoenix.CodeReloader` purged its defining module. `is_function/1` is true,
    # so this can only be the stale-code case — the same condition can never
    # arise in a compiled release, which never hot-swaps code.
    skipped = "GenServer terminating ** (BadFunctionError) #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"
    stale_fun = fn -> :ok end

    LogHandler.log(
      crash_event(:error, skipped, {%BadFunctionError{term: stale_fun}, []}),
      config()
    )

    LogHandler.log(event(:error, sentinel, %{component: :system}), config())

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, skipped).key) == nil
  end

  test "an UndefinedFunctionError for a module no longer loaded is not minted (renamed/removed module)" do
    # "module X is not available" only happens when the module has been purged
    # — either mid-reload or because it was permanently renamed/removed, as
    # happened when activity_widget_components.ex was split into per-subsystem
    # modules. A compiled release never purges modules at runtime.
    skipped = "GenServer terminating ** (UndefinedFunctionError) #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"

    LogHandler.log(
      crash_event(
        :error,
        skipped,
        {%UndefinedFunctionError{
           module: MediaCentaurWeb.NoSuchWidgetComponentsModule,
           function: :self_update_widget,
           arity: 1
         }, []}
      ),
      config()
    )

    LogHandler.log(event(:error, sentinel, %{component: :system}), config())

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, skipped).key) == nil
  end

  test "an UndefinedFunctionError for a module that IS loaded still mints — real bug, not stale code" do
    minted = "GenServer terminating ** (UndefinedFunctionError) #{uniq()}"

    LogHandler.log(
      crash_event(
        :error,
        minted,
        {%UndefinedFunctionError{
           module: MediaCentaur.ErrorReports.LogHandler,
           function: :nope,
           arity: 0
         }, []}
      ),
      config()
    )

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, minted).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, minted).key)
  end

  test "a PendingMigrationError from the dev repo-status plug is not minted (dev-only artifact)" do
    # `Phoenix.Ecto.CheckRepoStatus` is mounted only under `code_reloading?`:
    # source with a new migration got reloaded before `mix ecto.migrate` ran.
    # A compiled release never mounts the plug, so this cannot occur there.
    skipped = "** (Phoenix.Ecto.PendingMigrationError) pending migrations #{uniq()}"
    sentinel = "ordinary system error #{uniq()}"

    pending = %Phoenix.Ecto.PendingMigrationError{
      repo: MediaCentaur.Repo,
      directories: [],
      migration_opts: []
    }

    LogHandler.log(crash_event(:error, skipped, {pending, []}), config())
    LogHandler.log(event(:error, sentinel, %{component: :system}), config())

    # The sentinel's bucket read is a call, so it orders after the skipped cast.
    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, sentinel).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, skipped).key) == nil
  end
end
