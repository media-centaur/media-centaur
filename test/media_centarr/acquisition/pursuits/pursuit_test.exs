defmodule MediaCentarr.Acquisition.Pursuits.PursuitTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.Pursuit

  describe "create_changeset/1" do
    test "valid attrs produce a valid changeset starting in active state" do
      attrs = %{
        tmdb_id: "12345",
        tmdb_type: "movie",
        title: "Sample Movie",
        year: 2010,
        origin: "auto"
      }

      changeset = Pursuit.create_changeset(attrs)

      assert changeset.valid?
      assert changeset.changes.tmdb_id == "12345"
      assert changeset.changes.tmdb_type == "movie"
      assert changeset.changes.title == "Sample Movie"
      assert changeset.changes.origin == "auto"
      # default applies via DB; not present in changes when not set explicitly
      assert Ecto.Changeset.get_field(changeset, :state) == "active"
      assert Ecto.Changeset.get_field(changeset, :attempt_count) == 0
      assert Ecto.Changeset.get_field(changeset, :tried_release_guids) == []
    end

    test "TV episode pursuit captures season and episode numbers" do
      attrs = %{
        tmdb_id: "999",
        tmdb_type: "tv",
        title: "Sample Show",
        season_number: 1,
        episode_number: 3,
        origin: "auto"
      }

      changeset = Pursuit.create_changeset(attrs)

      assert changeset.valid?
      assert changeset.changes.season_number == 1
      assert changeset.changes.episode_number == 3
    end

    test "criteria map is cast verbatim" do
      attrs = %{
        tmdb_id: "1",
        tmdb_type: "movie",
        title: "T",
        origin: "auto",
        criteria: %{"min_quality" => "1080p", "max_quality" => "2160p"}
      }

      changeset = Pursuit.create_changeset(attrs)

      assert changeset.valid?
      assert changeset.changes.criteria == %{"min_quality" => "1080p", "max_quality" => "2160p"}
    end

    test "requires title and origin (tmdb_id / tmdb_type required only on TMDB recipe)" do
      changeset = Pursuit.create_changeset(%{})

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :title)
      assert Keyword.has_key?(changeset.errors, :origin)
    end

    test "TMDB recipe also requires tmdb_id and tmdb_type" do
      changeset =
        Pursuit.create_changeset(%{recipe_type: "tmdb", title: "T", origin: "auto"})

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :tmdb_id)
      assert Keyword.has_key?(changeset.errors, :tmdb_type)
    end

    test "prowlarr_query recipe requires manual_query (not TMDB fields)" do
      changeset =
        Pursuit.create_changeset(%{recipe_type: "prowlarr_query", title: "T", origin: "manual"})

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :manual_query)
      refute Keyword.has_key?(changeset.errors, :tmdb_id)
    end

    test "rejects unknown origin values" do
      attrs = %{tmdb_id: "1", tmdb_type: "movie", title: "T", origin: "bogus"}
      changeset = Pursuit.create_changeset(attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :origin)
    end
  end

  describe "set_awaiting_decision_changeset/2" do
    test "sets awaiting_decision_at when nil" do
      pursuit = %Pursuit{state: "active", awaiting_decision_at: nil}
      now = DateTime.utc_now(:second)
      changeset = Pursuit.set_awaiting_decision_changeset(pursuit, now)
      assert changeset.valid?
      assert changeset.changes.awaiting_decision_at == now
    end

    test "preserves existing timestamp on second call (idempotent)" do
      original = DateTime.add(DateTime.utc_now(:second), -3600, :second)
      pursuit = %Pursuit{state: "active", awaiting_decision_at: original}
      changeset = Pursuit.set_awaiting_decision_changeset(pursuit, DateTime.utc_now(:second))
      refute Map.has_key?(changeset.changes, :awaiting_decision_at)
    end
  end

  describe "clear_awaiting_decision_changeset/1" do
    test "clears the timestamp" do
      pursuit = %Pursuit{state: "active", awaiting_decision_at: DateTime.utc_now(:second)}
      changeset = Pursuit.clear_awaiting_decision_changeset(pursuit)
      assert changeset.changes.awaiting_decision_at == nil
    end
  end

  describe "satisfy_changeset/1" do
    test "transitions in-flight -> satisfied" do
      pursuit = %Pursuit{state: "active"}
      changeset = Pursuit.satisfy_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "satisfied"
    end

    test "rejects already-terminal pursuit" do
      pursuit = %Pursuit{state: "exhausted"}
      changeset = Pursuit.satisfy_changeset(pursuit)
      refute changeset.valid?
    end
  end

  describe "exhaust_changeset/1" do
    test "transitions in-flight -> exhausted" do
      pursuit = %Pursuit{state: "active"}
      changeset = Pursuit.exhaust_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "exhausted"
    end

    test "clears awaiting_decision_at when exhausting an awaiting pursuit" do
      pursuit = %Pursuit{state: "active", awaiting_decision_at: DateTime.utc_now(:second)}
      changeset = Pursuit.exhaust_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "exhausted"
      assert changeset.changes.awaiting_decision_at == nil
    end
  end

  describe "cancel_changeset/1" do
    test "transitions in-flight -> cancelled" do
      pursuit = %Pursuit{state: "active"}
      changeset = Pursuit.cancel_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "cancelled"
    end
  end

  describe "record_attempt_changeset/2" do
    test "increments attempt_count and appends a release guid to tried_release_guids" do
      pursuit = %Pursuit{attempt_count: 1, tried_release_guids: ["existing-guid"]}
      changeset = Pursuit.record_attempt_changeset(pursuit, "new-guid")

      assert changeset.valid?
      assert changeset.changes.attempt_count == 2
      assert changeset.changes.tried_release_guids == ["existing-guid", "new-guid"]
    end

    test "permits nil guid (failed attempt with no specific release)" do
      pursuit = %Pursuit{attempt_count: 0, tried_release_guids: []}
      changeset = Pursuit.record_attempt_changeset(pursuit, nil)

      assert changeset.valid?
      assert changeset.changes.attempt_count == 1
      refute Map.has_key?(changeset.changes, :tried_release_guids)
    end

    test "ignores duplicate guid (idempotent re-tries)" do
      pursuit = %Pursuit{attempt_count: 1, tried_release_guids: ["guid-a"]}
      changeset = Pursuit.record_attempt_changeset(pursuit, "guid-a")

      # attempt_count still bumps because it's a new attempt — the dedup is on the guid list
      assert changeset.valid?
      assert changeset.changes.attempt_count == 2
      refute Map.has_key?(changeset.changes, :tried_release_guids)
    end
  end
end
