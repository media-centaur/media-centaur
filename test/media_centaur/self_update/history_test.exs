defmodule MediaCentaur.SelfUpdate.HistoryTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.SelfUpdate.History

  describe "record_boot_version/1 + list/0" do
    test "records the version when the log is empty" do
      assert :ok = History.record_boot_version("0.82.0")

      assert [%{version: "0.82.0", recorded_at: %DateTime{}}] = History.list()
    end

    test "records a new entry, newest-first, when the version changed" do
      :ok = History.record_boot_version("0.82.0")
      :ok = History.record_boot_version("0.83.0")

      assert [%{version: "0.83.0"}, %{version: "0.82.0"}] = History.list()
    end

    test "is a no-op when the version is unchanged" do
      :ok = History.record_boot_version("0.82.0")
      :ok = History.record_boot_version("0.82.0")

      assert [%{version: "0.82.0"}] = History.list()
    end

    test "caps the stored list at 50 entries, dropping the oldest" do
      for n <- 1..55, do: History.record_boot_version("0.0.#{n}")

      entries = History.list()
      assert length(entries) == 50
      # newest-first: most recent recorded is the head, oldest survivors at the tail
      assert hd(entries).version == "0.0.55"
      assert List.last(entries).version == "0.0.6"
    end

    test "list/0 returns [] when nothing has been recorded" do
      assert History.list() == []
    end
  end

  describe "SelfUpdate.upgrade_history/0" do
    test "delegates to History.list/0, newest-first" do
      :ok = History.record_boot_version("0.82.0")
      :ok = History.record_boot_version("0.83.0")

      assert [%{version: "0.83.0"}, %{version: "0.82.0"}] =
               MediaCentaur.SelfUpdate.upgrade_history()
    end
  end
end
