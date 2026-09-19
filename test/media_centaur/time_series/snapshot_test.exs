defmodule MediaCentaur.TimeSeries.SnapshotTest do
  use MediaCentaur.Case, async: true

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

  test "a store loads its snapshot on boot and writes on shutdown", %{tmp_dir: dir} do
    path = Path.join(dir, "traffic.snapshot")
    suffix = System.unique_integer([:positive])
    # Wall-clock time: the boot sweep drops 10-second rows older than an hour.
    now = System.os_time(:second)
    table = :"snapshot_store_#{suffix}"
    name = :"snapshot_store_name_#{suffix}"

    pid =
      start_supervised!(
        {Store, name: name, table: table, schema: @schema, snapshot_path: path},
        id: name
      )

    Store.add(table, @schema, :tmdb, now, %{requests: 2, latency_max_ms: 90})
    :ok = stop_supervised!(name)
    refute Process.alive?(pid)
    assert File.exists?(path)

    table2 = :"snapshot_store_#{suffix}_b"
    name2 = :"snapshot_store_name_#{suffix}_b"

    start_supervised!(
      {Store, name: name2, table: table2, schema: @schema, snapshot_path: path},
      id: name2
    )

    assert [{_, %{requests: 2, latency_max_ms: 90}}] =
             Store.rows(table2, :"10s", :tmdb, now - 10, now)
  end
end
