defmodule MediaCentarr.Acquisition.ViewModels.PursuitStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Acquisition.ViewModels.PursuitStatus
  alias MediaCentarr.Downloads.QueueItem

  defp pursuit(state, attrs \\ %{}) do
    base = %Pursuit{
      id: "p-1",
      title: "Sample Movie",
      state: Atom.to_string(state),
      origin: "auto",
      tmdb_type: "movie",
      attempt_count: 0,
      tried_release_guids: []
    }

    struct(base, attrs)
  end

  defp target(status, attrs \\ %{}) do
    base = %Target{
      id: "t-1",
      status: Atom.to_string(status),
      title: "Sample Movie",
      release_title: "Sample.Movie.1080p.WEB-DL.mkv",
      attempt_count: 0
    }

    struct(base, attrs)
  end

  defp queue_item(state, attrs \\ %{}) do
    base = %QueueItem{
      id: "qi-1",
      title: "Sample.Movie.1080p.WEB-DL.mkv",
      state: state
    }

    struct(base, attrs)
  end

  describe "derive/3 — active + seeking" do
    test "Searching with cancel + request_decision" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:active), target(:seeking), nil)

      assert action.verb == "Searching"
      assert action.severity == :info
      assert next != nil
      assert :cancel in actions
      assert :request_decision in actions
    end

    test "description is timeless when next_attempt_at is nil (fresh target)" do
      {action, _next, _actions} =
        PursuitStatus.derive(
          pursuit(:active),
          target(:seeking, %{attempt_count: 3, next_attempt_at: nil}),
          nil
        )

      assert action.description == "Looking for an acceptable release (attempt 4)."
    end

    test "description surfaces the countdown when next_attempt_at is scheduled" do
      future = DateTime.add(DateTime.utc_now(), 2 * 3600 + 15 * 60, :second)

      {action, _next, _actions} =
        PursuitStatus.derive(
          pursuit(:active),
          target(:seeking, %{attempt_count: 3, next_attempt_at: future}),
          nil
        )

      assert action.description == "Next attempt in 2h 15m (attempt 4)."
    end
  end

  describe "derive/3 — active + acquired + queue states" do
    test "downloading -> Downloading, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), target(:acquired), queue_item(:downloading))

      assert action.verb == "Downloading"
      assert action.severity == :info
      assert actions == [:cancel]
    end

    test "queued -> Queued, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), target(:acquired), queue_item(:queued))

      assert action.verb == "Queued"
      assert actions == [:cancel]
    end

    test "stalled -> Stalled (warning) with change_target + request_decision" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), target(:acquired), queue_item(:stalled))

      assert action.verb == "Stalled"
      assert action.severity == :warning
      assert :change_target in actions
      assert :request_decision in actions
    end

    test "paused -> Paused" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), target(:acquired), queue_item(:paused))

      assert action.verb == "Paused"
      assert actions == [:cancel]
    end

    test "completed -> Verifying" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:active), target(:acquired), queue_item(:completed))

      assert action.verb == "Verifying"
      assert next.description =~ "InboundListener"
      assert actions == [:cancel]
    end

    test "error -> Error with change_target" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), target(:acquired), queue_item(:error))

      assert action.verb == "Error"
      assert action.severity == :error
      assert :change_target in actions
    end

    test "no queue match -> Waiting with change_target hint" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), target(:acquired), nil)

      assert action.verb == "Waiting"
      assert :change_target in actions
    end
  end

  describe "derive/3 — active + terminal-failure target states" do
    test "failed -> Stopped with change_target + request_decision" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), target(:failed), nil)

      assert action.verb == "Stopped"
      assert :change_target in actions
      assert :request_decision in actions
    end

    test "cancelled target -> Stopped with change_target" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), target(:cancelled), nil)

      assert action.verb == "Stopped"
      assert :change_target in actions
    end
  end

  describe "derive/3 — active + no target" do
    test "missing target -> Unknown with cancel + change_target" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), nil, nil)

      assert action.verb == "Unknown"
      assert action.severity == :warning
      assert :cancel in actions
      assert :change_target in actions
    end
  end

  describe "derive/3 — terminal pursuit states" do
    test "needs_decision -> Decision needed" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:needs_decision), target(:seeking), nil)

      assert action.verb == "Decision needed"
      assert actions == [:cancel]
    end

    test "satisfied -> Done, no actions, no next_step" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:satisfied), target(:acquired), nil)

      assert action.verb == "Done"
      assert action.severity == :success
      assert next == nil
      assert actions == []
    end

    test "exhausted -> Gave up, no actions" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:exhausted), target(:failed), nil)

      assert action.verb == "Gave up"
      assert action.severity == :error
      assert actions == []
    end

    test "cancelled -> Cancelled, no actions" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:cancelled), nil, nil)

      assert action.verb == "Cancelled"
      assert next == nil
      assert actions == []
    end
  end
end
