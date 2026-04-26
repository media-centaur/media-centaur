defmodule MediaCentarrWeb.Components.UpcomingCardsTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{Grab, QueueItem}
  alias MediaCentarrWeb.Components.UpcomingCards

  defp grab(status, overrides \\ %{}) do
    Map.merge(%Grab{status: status}, overrides)
  end

  defp queue(state, overrides \\ %{}) do
    Map.merge(%QueueItem{id: "q-1", title: "Q", state: state}, overrides)
  end

  describe "release_status/3 — completion takes precedence" do
    test ":completed when in_library, regardless of grab/queue" do
      assert UpcomingCards.release_status(true, nil, nil) == :completed

      assert UpcomingCards.release_status(true, grab("searching"), queue(:downloading)) ==
               :completed
    end
  end

  describe "release_status/3 — grabbed + queue state" do
    test ":downloading when grab is grabbed and queue item is :downloading" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:downloading)) ==
               :downloading
    end

    test ":downloading when grab is grabbed and queue item is :stalled (treat as live)" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:stalled)) ==
               :downloading
    end

    test ":paused when grab is grabbed and queue item is :paused" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:paused)) == :paused
    end

    test ":errored when grab is grabbed and queue item is :error" do
      assert UpcomingCards.release_status(false, grab("grabbed"), queue(:error)) == :errored
    end

    test ":downloading when grab is grabbed but no matching queue item (queued or imported)" do
      assert UpcomingCards.release_status(false, grab("grabbed"), nil) == :downloading
    end
  end

  describe "release_status/3 — searching states" do
    test ":searching when grab status is searching" do
      assert UpcomingCards.release_status(false, grab("searching"), nil) == :searching
    end

    test ":searching when grab status is snoozed" do
      assert UpcomingCards.release_status(false, grab("snoozed"), nil) == :searching
    end
  end

  describe "release_status/3 — terminal non-success states" do
    test ":abandoned when grab status is abandoned" do
      assert UpcomingCards.release_status(false, grab("abandoned"), nil) == :abandoned
    end

    test ":cancelled when grab status is cancelled (treated visually as no-op)" do
      assert UpcomingCards.release_status(false, grab("cancelled"), nil) == :cancelled
    end
  end

  describe "release_status/3 — no acquisition" do
    test ":none when there's no grab and not in library" do
      assert UpcomingCards.release_status(false, nil, nil) == :none
    end
  end
end
