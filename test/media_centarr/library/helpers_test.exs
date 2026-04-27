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

      # Use unique IDs so concurrent broadcasts from other tests can't
      # accidentally satisfy the membership assertion.
      entity_ids = ["helpers-test-#{System.unique_integer()}-#{:rand.uniform(100_000)}"]
      assert Helpers.broadcast_entities_changed(entity_ids) == :ok

      # The coalescer may bundle our IDs with IDs from concurrent test
      # broadcasts in the same 200ms window — assert each of our IDs is
      # present, not that the received list equals our list.
      assert_receive {:entities_changed, received_ids}, 500
      for id <- entity_ids, do: assert(id in received_ids)
    end
  end
end
