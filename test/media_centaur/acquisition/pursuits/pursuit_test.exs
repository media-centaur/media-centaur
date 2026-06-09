defmodule MediaCentaur.Acquisition.Pursuits.PursuitTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.Pursuit

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

  describe "fold_changeset/2" do
    test "same state is a no-op changeset" do
      pursuit = %Pursuit{state: "active"}
      changeset = Pursuit.fold_changeset(pursuit, "active")
      assert changeset.valid?
      assert changeset.changes == %{}
    end

    test "transitions in-flight to each terminal fold outcome" do
      for folded <- ~w(satisfied partial exhausted cancelled) do
        changeset = Pursuit.fold_changeset(%Pursuit{state: "active"}, folded)
        assert changeset.valid?
        assert changeset.changes.state == folded
      end
    end

    test "rejects a fold from an already-terminal state" do
      changeset = Pursuit.fold_changeset(%Pursuit{state: "exhausted"}, "satisfied")
      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :state)
    end
  end
end
