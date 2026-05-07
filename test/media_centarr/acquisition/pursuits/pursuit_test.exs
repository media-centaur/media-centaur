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

    test "requires tmdb_id, tmdb_type, title, origin" do
      changeset = Pursuit.create_changeset(%{})

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :tmdb_id)
      assert Keyword.has_key?(changeset.errors, :tmdb_type)
      assert Keyword.has_key?(changeset.errors, :title)
      assert Keyword.has_key?(changeset.errors, :origin)
    end

    test "rejects unknown origin values" do
      attrs = %{tmdb_id: "1", tmdb_type: "movie", title: "T", origin: "bogus"}
      changeset = Pursuit.create_changeset(attrs)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :origin)
    end
  end

  describe "request_decision_changeset/1" do
    test "transitions active -> needs_decision" do
      pursuit = %Pursuit{state: "active"}
      changeset = Pursuit.request_decision_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "needs_decision"
    end

    test "rejects transition from terminal state" do
      pursuit = %Pursuit{state: "satisfied"}
      changeset = Pursuit.request_decision_changeset(pursuit)
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :state)
    end
  end

  describe "resume_changeset/1" do
    test "transitions needs_decision -> active" do
      pursuit = %Pursuit{state: "needs_decision"}
      changeset = Pursuit.resume_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "active"
    end

    test "rejects transition from non-needs_decision state" do
      pursuit = %Pursuit{state: "active"}
      changeset = Pursuit.resume_changeset(pursuit)
      refute changeset.valid?
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

    test "permits transition from needs_decision -> exhausted (user gives up)" do
      pursuit = %Pursuit{state: "needs_decision"}
      changeset = Pursuit.exhaust_changeset(pursuit)
      assert changeset.valid?
      assert changeset.changes.state == "exhausted"
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
