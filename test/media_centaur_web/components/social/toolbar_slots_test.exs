defmodule MediaCentaurWeb.Components.Social.ToolbarSlotsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Social.ToolbarSlots

  defp facts(overrides),
    do: Map.merge(%{rung: nil, library_owner_id: nil, acquisition_state: nil}, overrides)

  test "the List slot: the verb below the list, Listed on it, Following above it" do
    assert %ToolbarSlots{list: :list, rung: nil} = ToolbarSlots.resolve(facts(%{}))
    assert %ToolbarSlots{list: :listed, rung: :list} = ToolbarSlots.resolve(facts(%{rung: :list}))

    assert %ToolbarSlots{list: :list, rung: :ignored} = ToolbarSlots.resolve(facts(%{rung: :ignored}))

    for rung <- [:follow, :grab],
        do: assert(%ToolbarSlots{list: :following} = ToolbarSlots.resolve(facts(%{rung: rung})))
  end

  test "the Download slot: In library wins, then the acquisition marker, else the verb" do
    assert %ToolbarSlots{download: :download} = ToolbarSlots.resolve(facts(%{}))

    assert %ToolbarSlots{download: {:state, "In library"}, library_owner_id: "owner"} =
             ToolbarSlots.resolve(facts(%{library_owner_id: "owner", acquisition_state: :downloading}))

    assert %ToolbarSlots{download: {:state, "Downloading"}, acquisition_state: :downloading} =
             ToolbarSlots.resolve(facts(%{acquisition_state: :downloading}))

    assert %ToolbarSlots{download: {:state, "Planning"}} =
             ToolbarSlots.resolve(facts(%{acquisition_state: :planning}))

    assert %ToolbarSlots{download: {:state, "Needs review"}} =
             ToolbarSlots.resolve(facts(%{acquisition_state: :needs_review}))
  end

  test "extra keys on an enriched row are ignored" do
    assert %ToolbarSlots{list: :list} =
             ToolbarSlots.resolve(Map.put(facts(%{}), :activity, :anything))
  end
end
