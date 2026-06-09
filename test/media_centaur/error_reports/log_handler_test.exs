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

  test "an unusual transport reason still mints — we don't blind ourselves" do
    minted = "Unrecoverable error: emfile #{uniq()}"

    LogHandler.log(
      crash_event(:error, minted, {%Bandit.TransportError{error: :emfile, message: minted}, []}),
      config()
    )

    assert Buckets.get_bucket(:lh_buckets, Fingerprint.fingerprint(:system, minted).key)
    assert Store.get_incident_by_fingerprint(Fingerprint.fingerprint(:system, minted).key)
  end
end
