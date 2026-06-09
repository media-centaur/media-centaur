defmodule MediaCentaur.Runtime.VitalsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Runtime.Vitals

  test "snapshot/0 returns well-formed, in-bounds runtime vitals" do
    snap = Vitals.snapshot()

    assert is_integer(snap.uptime_seconds) and snap.uptime_seconds >= 0

    assert %{total: total, processes: processes, ets: ets, binary: binary} = snap.memory
    assert total > 0 and processes > 0 and ets >= 0 and binary >= 0

    assert snap.process_count > 0
    assert snap.process_limit >= snap.process_count
    assert snap.run_queue >= 0
    assert snap.schedulers > 0

    assert %{otp: otp, elixir: elixir, os: os, version: version} = snap.host
    assert is_binary(otp) and is_binary(elixir) and is_binary(os) and is_binary(version)

    assert %{size_bytes: db_size, wal_bytes: wal} = snap.db
    assert is_integer(db_size) and db_size >= 0
    assert is_integer(wal) and wal >= 0
  end
end
