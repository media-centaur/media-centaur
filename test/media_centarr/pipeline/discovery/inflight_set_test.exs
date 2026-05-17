defmodule MediaCentarr.Pipeline.Discovery.InflightSetTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Pipeline.Discovery.InflightSet

  setup do
    # The InflightSet starts under the application supervision tree at
    # test load; reset it before each test so cases don't leak state.
    :ets.delete_all_objects(:pipeline_discovery_inflight)
    :ok
  end

  describe "claim/1" do
    test "returns true the first time a path is claimed" do
      assert InflightSet.claim("/media/test/first.mkv") == true
    end

    test "returns false when the path is already in flight" do
      assert InflightSet.claim("/media/test/dup.mkv") == true
      assert InflightSet.claim("/media/test/dup.mkv") == false
    end

    test "independent paths are independent" do
      assert InflightSet.claim("/media/test/a.mkv") == true
      assert InflightSet.claim("/media/test/b.mkv") == true
      assert InflightSet.size() == 2
    end
  end

  describe "release/1" do
    test "lets a previously-claimed path be re-claimed" do
      assert InflightSet.claim("/media/test/cycle.mkv") == true
      assert :ok = InflightSet.release("/media/test/cycle.mkv")
      assert InflightSet.claim("/media/test/cycle.mkv") == true
    end

    test "is a no-op on an unclaimed path" do
      assert :ok = InflightSet.release("/media/test/never-claimed.mkv")
      assert InflightSet.size() == 0
    end
  end

  describe "size/0" do
    test "reports the current in-flight count" do
      assert InflightSet.size() == 0
      InflightSet.claim("/a.mkv")
      InflightSet.claim("/b.mkv")
      assert InflightSet.size() == 2
      InflightSet.release("/a.mkv")
      assert InflightSet.size() == 1
    end
  end
end
