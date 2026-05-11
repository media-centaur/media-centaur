defmodule MediaCentarr.Acquisition.ViewModels.PursuitStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
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

  defp grab(status, attrs \\ %{}) do
    base = %Grab{
      id: "g-1",
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

  describe "derive/3 — active + searching" do
    test "Searching with cancel-only actions" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:active), grab(:searching), nil)

      assert action.verb == "Searching"
      assert action.severity == :info
      assert next != nil
      assert actions == [:cancel]
    end
  end

  describe "derive/3 — active + snoozed" do
    test "Snoozed with cancel + re_search + request_decision" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:active), grab(:snoozed), nil)

      assert action.verb == "Snoozed"
      assert action.severity == :info
      assert next != nil
      assert :cancel in actions
      assert :re_search in actions
      assert :request_decision in actions
    end
  end

  describe "derive/3 — active + grabbed + queue states" do
    test "downloading -> Downloading, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:downloading))

      assert action.verb == "Downloading"
      assert action.severity == :info
      assert actions == [:cancel]
    end

    test "queued -> Queued, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:queued))

      assert action.verb == "Queued"
      assert actions == [:cancel]
    end

    test "stalled -> Stalled (warning) with re_search + request_decision" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:stalled))

      assert action.verb == "Stalled"
      assert action.severity == :warning
      assert :re_search in actions
      assert :request_decision in actions
    end

    test "paused -> Paused" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:paused))

      assert action.verb == "Paused"
      assert actions == [:cancel]
    end

    test "completed -> Verifying" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:completed))

      assert action.verb == "Verifying"
      assert next.description =~ "InboundListener"
      assert actions == [:cancel]
    end

    test "error -> Error with re_search" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), grab(:grabbed), queue_item(:error))

      assert action.verb == "Error"
      assert action.severity == :error
      assert :re_search in actions
    end

    test "no queue match -> Waiting with re_search hint" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), grab(:grabbed), nil)

      assert action.verb == "Waiting"
      assert :re_search in actions
    end
  end

  describe "derive/3 — active + terminal-failure grab states" do
    test "abandoned -> Stopped with all manual triggers" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), grab(:abandoned), nil)

      assert action.verb == "Stopped"
      assert :re_search in actions
      assert :request_decision in actions
    end

    test "cancelled grab -> Stopped with re_search" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), grab(:cancelled), nil)

      assert action.verb == "Stopped"
      assert :re_search in actions
    end
  end

  describe "derive/3 — manual-origin pursuits substitute :request_decision for :re_search" do
    # Manual-origin pursuits have `tmdb_type: "manual"` and no TMDB metadata,
    # so the auto-grab SearchAndGrab pipeline (driven by QueryBuilder which
    # only handles movie/tv types) cannot re-search them — it raises
    # FunctionClauseError in a retry loop. The decision-card flow is the
    # right recovery path for manual pursuits: it surfaces fresh Prowlarr
    # results for the user to pick. The view model swaps the action so the
    # UI never offers a broken button.

    test "active + grabbed + no queue: :re_search becomes :request_decision" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active, %{origin: "manual"}), grab(:grabbed), nil)

      assert action.verb == "Waiting"
      refute :re_search in actions
      assert :request_decision in actions
      assert :cancel in actions
    end

    test "active + abandoned: :re_search becomes :request_decision" do
      {_action, _next, actions} =
        PursuitStatus.derive(pursuit(:active, %{origin: "manual"}), grab(:abandoned), nil)

      refute :re_search in actions
      assert :request_decision in actions
    end

    test "active + cancelled grab: :re_search becomes :request_decision" do
      {_action, _next, actions} =
        PursuitStatus.derive(pursuit(:active, %{origin: "manual"}), grab(:cancelled), nil)

      refute :re_search in actions
      assert :request_decision in actions
    end

    test "auto-origin pursuits still get :re_search (sanity)" do
      {_action, _next, actions} =
        PursuitStatus.derive(pursuit(:active, %{origin: "auto"}), grab(:grabbed), nil)

      assert :re_search in actions
    end
  end

  describe "derive/3 — active + no grab" do
    test "missing grab -> Unknown with cancel-only" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), nil, nil)

      assert action.verb == "Unknown"
      assert action.severity == :warning
      assert actions == [:cancel]
    end
  end

  describe "derive/3 — terminal pursuit states" do
    test "needs_decision -> Decision needed" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:needs_decision), grab(:snoozed), nil)

      assert action.verb == "Decision needed"
      assert actions == [:cancel]
    end

    test "satisfied -> Done, no actions, no next_step" do
      {action, next, actions} = PursuitStatus.derive(pursuit(:satisfied), grab(:grabbed), nil)

      assert action.verb == "Done"
      assert action.severity == :success
      assert next == nil
      assert actions == []
    end

    test "exhausted -> Gave up, no actions" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:exhausted), grab(:abandoned), nil)

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
