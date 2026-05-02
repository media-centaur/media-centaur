defmodule MediaCentarr.Library.BroadcastCoalescerTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Library.BroadcastCoalescer
  alias MediaCentarr.Topics

  setup do
    # The coalescer is started by the application; subscribe to its output.
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
    :ok
  end

  test "coalesces a burst into a single broadcast" do
    # Send 100 enqueue calls in rapid succession.
    for i <- 1..100, do: BroadcastCoalescer.enqueue([i])

    # Should receive exactly one broadcast within the flush window.
    assert_receive {:entities_changed, %{entity_ids: ids}}, 500
    assert length(ids) == 100
    assert Enum.sort(ids) == Enum.to_list(1..100)

    # No second broadcast.
    refute_receive {:entities_changed, _}, 500
  end

  test "deduplicates identical IDs across calls" do
    BroadcastCoalescer.enqueue([1, 2, 3])
    BroadcastCoalescer.enqueue([2, 3, 4])
    BroadcastCoalescer.enqueue([4, 5])

    assert_receive {:entities_changed, %{entity_ids: ids}}, 500
    assert Enum.sort(ids) == [1, 2, 3, 4, 5]
  end

  test "starts a new flush window after the previous flushed" do
    BroadcastCoalescer.enqueue([1])
    assert_receive {:entities_changed, %{entity_ids: [1]}}, 500

    # Wait for the timer to clear, then enqueue again — should produce a new broadcast.
    BroadcastCoalescer.enqueue([2])
    assert_receive {:entities_changed, %{entity_ids: [2]}}, 500
  end
end
