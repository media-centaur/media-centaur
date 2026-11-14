defmodule MediaCentaur.ReleaseTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Release

  describe "snapshot_due?/2" do
    test "a database with applied migrations and a pending schema migration is copied first" do
      assert Release.snapshot_due?([{:up, 1, "first"}, {:down, 2, "second"}], false)
    end

    test "a database with applied migrations and a pending data migration is copied first" do
      assert Release.snapshot_due?([{:up, 1, "first"}, {:up, 2, "second"}], true)
    end

    test "a database with nothing pending is not copied" do
      refute Release.snapshot_due?([{:up, 1, "first"}, {:up, 2, "second"}], false)
    end

    test "a new database, with no migration applied, is not copied" do
      refute Release.snapshot_due?([{:down, 1, "first"}, {:down, 2, "second"}], true)
    end
  end
end
