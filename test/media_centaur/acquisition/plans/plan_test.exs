defmodule MediaCentaur.Acquisition.Plans.PlanTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.TMDB.Title

  @base %{tmdb_id: "777", tmdb_type: "movie", title: "Sample Movie"}

  describe "create_changeset/1 approval_policy" do
    test "defaults to review" do
      changeset = Plan.create_changeset(@base)
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :approval_policy) == "review"
    end

    test "accepts automatic" do
      changeset = Plan.create_changeset(Map.put(@base, :approval_policy, "automatic"))
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :approval_policy) == "automatic"
    end

    test "rejects any other value" do
      changeset = Plan.create_changeset(Map.put(@base, :approval_policy, "approve"))
      refute changeset.valid?
      assert %{approval_policy: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "tmdb_title/1" do
    test "a movie plan reads as the app-wide title value" do
      plan = %Plan{tmdb_id: "246813", tmdb_type: "movie", title: "Sample Movie", year: 2005}

      assert %Title{tmdb_id: 246_813, media_type: :movie, name: "Sample Movie", year: "2005"} =
               Plan.tmdb_title(plan)
    end

    test "a series plan, with no year known" do
      plan = %Plan{tmdb_id: "246810", tmdb_type: "tv", title: "Sample Show"}

      assert %Title{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show", year: nil} =
               Plan.tmdb_title(plan)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
