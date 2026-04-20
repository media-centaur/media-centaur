defmodule MediaCentarr.Controls.CatalogTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Controls.Catalog

  test "all/0 returns 11 bindings" do
    assert length(Catalog.all()) == 11
  end

  test "all binding ids are unique" do
    ids = Enum.map(Catalog.all(), & &1.id)
    assert length(ids) == length(Enum.uniq(ids))
  end

  test "every binding has a category in the valid set" do
    valid = [:navigation, :zones, :playback, :system]
    assert Enum.all?(Catalog.all(), &(&1.category in valid))
  end

  test "default_key values are unique (excluding nil)" do
    keys = Catalog.all() |> Enum.map(& &1.default_key) |> Enum.reject(&is_nil/1)
    assert length(keys) == length(Enum.uniq(keys)), "duplicate default_key in catalog"
  end

  test "default_button values are unique (excluding nil)" do
    buttons = Catalog.all() |> Enum.map(& &1.default_button) |> Enum.reject(&is_nil/1)
    assert length(buttons) == length(Enum.uniq(buttons)), "duplicate default_button in catalog"
  end

  test "get/1 returns a binding by id" do
    assert %{id: :navigate_up, name: "Move up"} = Catalog.get(:navigate_up)
  end

  test "get/1 returns nil for unknown id" do
    assert Catalog.get(:nope) == nil
  end

  test "by_category/1 groups correctly" do
    nav = Catalog.by_category(:navigation)
    assert Enum.all?(nav, &(&1.category == :navigation))
    assert length(nav) == 7
  end

  test "toggle_console is in :system category with scope :global" do
    binding = Catalog.get(:toggle_console)
    assert binding.category == :system
    assert binding.scope == :global
    assert binding.default_key == "`"
  end
end
