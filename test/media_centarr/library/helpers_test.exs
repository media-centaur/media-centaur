defmodule MediaCentarr.Library.HelpersTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Library.Helpers
  alias MediaCentarr.Topics

  describe "broadcast_entities_changed/1" do
    test "empty list is a no-op and returns :ok" do
      :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())

      assert Helpers.broadcast_entities_changed([]) == :ok

      refute_receive {:entities_changed, _}, 50
    end

    test "non-empty list enqueues IDs for broadcast within the coalescer flush window" do
      :ok = Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())

      entity_ids = ["entity-1", "entity-2"]
      assert Helpers.broadcast_entities_changed(entity_ids) == :ok

      assert_receive {:entities_changed, received_ids}, 500
      assert Enum.sort(received_ids) == Enum.sort(entity_ids)
    end
  end
end
