defmodule MediaCentaur.TimeSeries.SnapshotTest do
  use MediaCentaur.Case, async: true

  import ExUnit.CaptureLog

  alias MediaCentaur.TimeSeries.{Schema, Snapshot, Store}

  @schema Schema.new(requests: :sum, latency_max_ms: :max)

  @moduletag :tmp_dir

  test "write then read round-trips rows", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    rows = [{{:"10s", :tmdb, 1_789_800_010}, 3, 180}, {{:"1h", :tmdb, 1_789_800_000}, 3, 180}]

    assert :ok = Snapshot.write(path, @schema, rows)
    assert {:ok, read} = Snapshot.read(path, @schema)
    assert Enum.sort(read) == Enum.sort(rows)
    refute File.exists?(path <> ".tmp")
  end

  test "a missing file is empty", %{tmp_dir: dir} do
    assert Snapshot.read(Path.join(dir, "none.snapshot"), @schema) == :empty
  end

  test "a file written for other fields is rejected", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    :ok = Snapshot.write(path, Schema.new(other: :sum), [{{:"10s", :tmdb, 1}, 1}])
    assert {:error, :schema_mismatch} = Snapshot.read(path, @schema)
  end

  test "garbage is rejected", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    File.write!(path, "not a snapshot")
    assert {:error, _} = Snapshot.read(path, @schema)
  end

  # Regression: a dev VM loads modules lazily, so on a cold boot the atoms a
  # snapshot names (resolutions, upstream ids) may not exist yet. Decoding
  # with `[:safe]` then rejected a valid file as `:corrupt` and the store
  # started empty (incident a67dde4ce96a2c0b, 2026-09-26).
  test "a file naming an atom this VM has not created yet is read", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    placeholder = "key_placeholder_000000"
    unseen = "key_unseen_" <> String.pad_leading("#{System.unique_integer([:positive])}", 11, "0")
    rows = [{{:"10s", String.to_atom(placeholder), 1_789_800_010}, 3, 180}]
    :ok = Snapshot.write(path, @schema, rows)

    # Swap the atom's text for one of the same length that no code has
    # created: the file is what a previous VM wrote about a key this one
    # has not loaded.
    <<131, 80, _size::32, compressed::binary>> = File.read!(path)
    binary = compressed |> :zlib.uncompress() |> String.replace(placeholder, unseen)
    File.write!(path, <<131, 80, byte_size(binary)::32>> <> :zlib.compress(binary))

    assert {:ok, [{{:"10s", key, 1_789_800_010}, 3, 180}]} = Snapshot.read(path, @schema)
    assert Atom.to_string(key) == unseen
  end

  test "a store says why it ignored a snapshot, under its tenant's component", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    File.write!(path, "not a snapshot")

    log =
      capture_log([level: :info, format: "[$level][$metadata]$message\n", metadata: [:component]], fn ->
        start_store(path)
      end)

    assert [line] = log |> String.split("\n") |> Enum.filter(&String.contains?(&1, path))
    assert line =~ "[warning][component=http ]"
    assert line =~ ":corrupt"
  end

  test "a snapshot from other fields is an expected discard, not a warning", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    :ok = Snapshot.write(path, Schema.new(other: :sum), [{{:"10s", :tmdb, 1}, 1}])

    # A warning would mint a `:log` incident; the test env's floor is
    # `:warning`, so the info line itself is not observable here. Only this
    # module's stores log about snapshots, and its tests run one at a time.
    log = capture_log([level: :warning], fn -> start_store(path) end)

    refute log =~ "time series snapshot"
  end

  defp start_store(path) do
    suffix = System.unique_integer([:positive])

    start_supervised!(
      {Store,
       name: :"snapshot_log_store_#{suffix}",
       table: :"snapshot_log_table_#{suffix}",
       schema: @schema,
       component: :http,
       snapshot_path: path},
      id: suffix
    )
  end

  test "a store loads its snapshot on boot and writes on shutdown", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    suffix = System.unique_integer([:positive])
    # Wall-clock time: the boot sweep drops 10-second rows older than an hour.
    now = System.os_time(:second)
    table = :"snapshot_store_#{suffix}"
    name = :"snapshot_store_name_#{suffix}"

    pid =
      start_supervised!(
        {Store, name: name, table: table, schema: @schema, component: :system, snapshot_path: path},
        id: name
      )

    Store.add(table, @schema, :tmdb, now, %{requests: 2, latency_max_ms: 90})
    :ok = stop_supervised!(name)
    refute Process.alive?(pid)
    assert File.exists?(path)

    table2 = :"snapshot_store_#{suffix}_b"
    name2 = :"snapshot_store_name_#{suffix}_b"

    start_supervised!(
      {Store, name: name2, table: table2, schema: @schema, component: :system, snapshot_path: path},
      id: name2
    )

    assert [{_, %{requests: 2, latency_max_ms: 90}}] =
             Store.rows(table2, :"10s", :tmdb, now - 10, now)
  end
end
