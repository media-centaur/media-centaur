defmodule MediaCentarrWeb.Components.ContinueWatchingRowTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Components.ContinueWatchingRow.Item

  test "Item struct enforces an :entity_id field at construction time" do
    assert_raise ArgumentError, fn ->
      struct!(Item, %{
        id: 1,
        name: "Foo",
        progress_pct: 30,
        backdrop_url: nil
      })
    end
  end
end
