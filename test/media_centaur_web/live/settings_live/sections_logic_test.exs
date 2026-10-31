defmodule MediaCentaurWeb.SettingsLive.SectionsLogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.SettingsLive.SectionsLogic

  @sections [
    %{id: "system", label: "System"},
    %{id: "social", label: "Social", feature: :social},
    %{id: "players", label: "Players", feature: :players}
  ]

  describe "visible/2" do
    test "a section without a feature is always listed" do
      assert Enum.map(SectionsLogic.visible(@sections, MapSet.new()), & &1.id) == ["system"]
    end

    test "a section is listed while its feature is on, in the list's order" do
      visible = SectionsLogic.visible(@sections, MapSet.new([:players, :social]))
      assert Enum.map(visible, & &1.id) == ["system", "social", "players"]

      visible = SectionsLogic.visible(@sections, MapSet.new([:players]))
      assert Enum.map(visible, & &1.id) == ["system", "players"]
    end
  end

  describe "hidden_feature/3" do
    test "names the feature hiding a section while it is off" do
      assert %{id: :social} = SectionsLogic.hidden_feature(@sections, "social", MapSet.new())
    end

    test "is nil for a visible section, one without a feature, and an unknown id" do
      assert SectionsLogic.hidden_feature(@sections, "social", MapSet.new([:social])) == nil
      assert SectionsLogic.hidden_feature(@sections, "system", MapSet.new()) == nil
      assert SectionsLogic.hidden_feature(@sections, "nowhere", MapSet.new()) == nil
    end
  end
end
