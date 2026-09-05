defmodule MediaCentaur.Acquisition.Plans.PlanTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Plans.Plan

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

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
