defmodule MediaCentaur.Acquisition.Pursuits.StageTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.{Stage, StatusContext}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Downloads.{QueueItem, QueueState}

  @now ~U[2026-09-21 12:00:00Z]
  @window 30

  defp context(attrs \\ %{}) do
    struct(
      %StatusContext{
        now: @now,
        handoff_window_minutes: @window,
        client_reachable?: true,
        pending_file_paths: MapSet.new()
      },
      attrs
    )
  end

  defp target(status, attrs \\ %{}) do
    struct(
      %Target{
        id: "t-1",
        status: Atom.to_string(status),
        title: "Sample Movie",
        release_title: "Sample.Movie.1080p.WEB-DL.mkv"
      },
      attrs
    )
  end

  defp acquired(attrs), do: target(:acquired, Map.put_new(attrs, :acquired_at, @now))

  defp ago(seconds), do: DateTime.add(@now, -seconds, :second)

  defp stage(target, queue_item \\ nil, location \\ :none),
    do: Stage.of(target, queue_item, location, context())

  describe "of/5 — target status maps straight through" do
    test "no target at all" do
      assert stage(nil) == :no_target
    end

    test "seeking, succeeded, failed and cancelled ignore every download input" do
      item = %QueueItem{id: "qi-1", title: "Sample.Movie.1080p.WEB-DL.mkv", state: :downloading}

      assert stage(target(:seeking), item, :in_review) == :seeking
      assert stage(target(:succeeded), item, :in_review) == :done
      assert stage(target(:failed), item, :in_review) == :failed
      assert stage(target(:cancelled), item, :in_review) == :cancelled
    end
  end

  describe "of/5 — acquired, the stage the queue snapshot cannot decide alone" do
    test "handed off: accepted by Prowlarr, not yet shown by the client" do
      assert stage(acquired(%{acquired_at: ago(20)})) == :handed_off
    end

    test "still handed off right up to the window boundary" do
      assert stage(acquired(%{acquired_at: ago(@window * 60 - 1)})) == :handed_off
    end

    test "missing: the window elapsed and the client never showed it" do
      assert stage(acquired(%{acquired_at: ago(@window * 60)})) == :missing
    end

    test "left the client: seen before, gone now" do
      target = acquired(%{acquired_at: ago(7200), first_seen_in_queue_at: ago(7000)})

      assert stage(target) == :left_client
    end

    test "a first sighting means an old hand-off is never called missing" do
      target = acquired(%{acquired_at: ago(86_400), first_seen_in_queue_at: ago(86_000)})

      assert stage(target) == :left_client
    end

    test "a target with no hand-off stamp is never accused of never arriving" do
      assert stage(acquired(%{acquired_at: nil})) == :handed_off
    end
  end

  describe "of/5 — precedence: evidence beats inference" do
    test "a live queue item outranks every other signal" do
      item = %QueueItem{id: "qi-1", title: "Sample.Movie.1080p.WEB-DL.mkv", state: :downloading}

      assert stage(acquired(%{acquired_at: ago(86_400)}), item, :in_review) == :at_client
      assert stage(acquired(%{first_seen_in_queue_at: ago(10)}), item) == :at_client
    end

    test "a file in review outranks a missing first-sighting stamp" do
      # A download fast enough to appear and vanish between two observation
      # passes is never stamped — the file in review is the stronger evidence.
      assert stage(acquired(%{acquired_at: ago(86_400)}), nil, :in_review) == :in_review
    end

    test "review beats left_client so a landed file never reads as merely gone" do
      target = acquired(%{acquired_at: ago(7200), first_seen_in_queue_at: ago(7000)})

      assert stage(target, nil, :in_review) == :in_review
    end
  end

  describe "of/4 — an unreachable client makes no accusation" do
    test "silence from a client that is not answering is not evidence" do
      target = acquired(%{acquired_at: ago(86_400)})

      assert Stage.of(target, nil, :none, context(%{client_reachable?: false})) == :handed_off
    end

    test "a blip between healthy polls still counts as answering" do
      assert QueueState.answering?(%QueueState{connectivity: :live})
      assert QueueState.answering?(%QueueState{connectivity: {:transient_failure, @now}})
      refute QueueState.answering?(%QueueState{connectivity: {:offline, @now}})
      refute QueueState.answering?(%QueueState{connectivity: :not_configured})
      refute QueueState.answering?(%QueueState{connectivity: :initializing})
      refute QueueState.answering?(%QueueState{connectivity: :auth_failed})
    end
  end
end
