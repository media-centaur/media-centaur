defmodule MediaCentaur.FeaturesTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Features
  alias MediaCentaur.Features.Feature
  alias MediaCentaur.Settings
  alias MediaCentaur.Topics

  describe "the registry" do
    test "every feature is declared once, with a stage and a one-line description" do
      ids = Enum.map(Features.all(), & &1.id)
      assert ids == Enum.uniq(ids)

      for %Feature{} = feature <- Features.all() do
        assert is_atom(feature.id)
        assert is_binary(feature.name) and feature.name != ""
        assert is_binary(feature.description) and feature.description != ""
        assert is_boolean(feature.default)
        assert feature.stage in [:development, :optional]
      end
    end

    test "get/1 and find/1 answer the registry; an unknown id is nil" do
      assert %Feature{id: :social, name: "Social"} = Features.get(:social)
      assert %Feature{id: :apps} = Features.find("apps")
      assert Features.get(:not_a_feature) == nil
      assert Features.find("not_a_feature") == nil
    end

    test "key/1 and feature_key?/1 agree on the Settings key" do
      assert Features.key(:social) == "feature:social"
      assert Features.feature_key?("feature:social")
      refute Features.feature_key?("show_social")
    end
  end

  describe "the flag" do
    test "enabled?/1 answers the default while nothing is stored" do
      assert Features.enabled?(:social) == Features.get(:social).default
      assert Features.enabled?(:apps) == Features.get(:apps).default
    end

    test "set/2 persists the flag and enabled?/1 reads it back" do
      refute Features.enabled?(:apps)
      Features.set(:apps, true)
      assert Features.enabled?(:apps)
      Features.set(:apps, false)
      refute Features.enabled?(:apps)
    end

    test "a stored value that is not a boolean falls back to the default" do
      Settings.find_or_create_entry!(%{key: Features.key(:social), value: %{"enabled" => "no"}})
      assert Features.enabled?(:social) == Features.get(:social).default
    end

    test "enabled/0 is the set of features that are on" do
      enabled = Features.enabled()
      assert MapSet.member?(enabled, :social)
      refute MapSet.member?(enabled, :apps)

      Features.set(:apps, true)
      Features.set(:social, false)

      enabled = Features.enabled()
      assert MapSet.member?(enabled, :apps)
      refute MapSet.member?(enabled, :social)
    end

    test "set/2 broadcasts the Settings change under the feature's key" do
      Topics.subscribe(Topics.settings_updates())
      Features.set(:apps, true)
      assert_receive {:setting_changed, "feature:apps", %{"enabled" => true}}
    end

    test "set/2 refuses an unknown feature" do
      assert_raise ArgumentError, fn -> Features.set(:not_a_feature, true) end
    end
  end
end
