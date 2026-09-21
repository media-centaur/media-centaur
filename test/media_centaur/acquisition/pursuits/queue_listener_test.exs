defmodule MediaCentaur.Acquisition.Pursuits.QueueListenerTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query
  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, QueueListener}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.{QueueItem, QueueState}

  @release "Sample.Release.2024.1080p-GRP"

  defp queue_state(items, connectivity \\ :live) do
    %QueueState{items: items, connectivity: connectivity}
  end

  defp queue_item(attrs \\ %{}) do
    struct!(%QueueItem{id: "HASH", title: @release, state: :downloading}, attrs)
  end

  defp acquired_pursuit(attrs \\ %{}) do
    create_pursuit_with_target(
      Map.merge(
        %{recipe_type: "prowlarr_query", release_title: @release, status: "acquired"},
        attrs
      )
    )
  end

  defp reload(%Target{} = target), do: Repo.get!(Target, target.id)

  defp download_started(pursuit_id) do
    Event
    |> where([e], e.pursuit_id == ^pursuit_id and e.kind == "download_started")
    |> Repo.all()
  end

  describe "observe/1" do
    test "stamps every in-flight target the snapshot shows" do
      {_pursuit, target} = acquired_pursuit()

      assert QueueListener.observe(queue_state([queue_item()])) == 1
      assert reload(target).first_seen_in_queue_at
    end

    test "a season pack's units are observed once, not once per episode" do
      # One release is one target however many units it covers
      # (Pursuits.TargetUnit), so a pack must put one beat on the timeline
      # rather than one per episode — the regression the pursuit-level
      # observation was introduced to fix, kept here at the right level.
      {pursuit, target} = acquired_pursuit()

      Enum.each(1..3, fn position ->
        create_pursuit_unit(pursuit, %{current_target_id: target.id, position: position})
      end)

      assert QueueListener.observe(queue_state([queue_item()])) == 1
      assert length(download_started(pursuit.id)) == 1
    end

    test "a composite holding several releases observes each of them" do
      {pursuit, first} = acquired_pursuit()

      second =
        create_covering_target(pursuit, [create_pursuit_unit(pursuit, %{position: 1})], %{
          status: "acquired",
          release_title: "Sample.Other.2024.1080p-GRP"
        })

      items = [queue_item(), queue_item(%{id: "HASH2", title: "Sample.Other.2024.1080p-GRP"})]

      assert QueueListener.observe(queue_state(items)) == 2
      assert reload(first).first_seen_in_queue_at
      assert reload(second).first_seen_in_queue_at
    end

    test "an offline client stamps nothing — its silence is not evidence" do
      {_pursuit, target} = acquired_pursuit()
      offline = queue_state([], {:offline, DateTime.utc_now(:second)})

      QueueListener.observe(offline)

      refute reload(target).first_seen_in_queue_at
    end

    test "a blip between healthy polls still counts as an answer" do
      {_pursuit, target} = acquired_pursuit()
      blip = queue_state([queue_item()], {:transient_failure, DateTime.utc_now(:second)})

      QueueListener.observe(blip)

      assert reload(target).first_seen_in_queue_at
    end

    test "no active pursuits is a clean no-op" do
      assert QueueListener.observe(queue_state([queue_item()])) == 0
    end

    test "terminal pursuits are not observed" do
      {_pursuit, target} = acquired_pursuit(%{state: "satisfied"})

      assert QueueListener.observe(queue_state([queue_item()])) == 0
      refute reload(target).first_seen_in_queue_at
    end
  end
end
