defmodule MediaCentaur.Acquisition.ViewModels.PursuitStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, Unit}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Acquisition.ViewModels.PursuitStatus
  alias MediaCentaur.Downloads.QueueItem

  defp pursuit(state, attrs \\ %{}) do
    base = %Pursuit{
      id: "p-1",
      title: "Sample Movie",
      state: Atom.to_string(state),
      origin: "auto",
      tmdb_type: "movie"
    }

    struct(base, attrs)
  end

  defp unit(attrs \\ %{}) do
    base = %Unit{
      id: "u-1",
      pursuit_id: "p-1",
      state: "active",
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
      {action, next, actions} = PursuitStatus.derive(pursuit(:active), unit(), target(:seeking), nil)

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
          unit(),
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
          unit(),
          target(:seeking, %{attempt_count: 3, next_attempt_at: future}),
          nil
        )

      assert action.description == "Next attempt in 2h 15m (attempt 4)."
    end
  end

  describe "derive/3 — active + acquired + queue states" do
    test "downloading -> Downloading, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(:downloading))

      assert action.verb == "Downloading"
      assert action.severity == :info
      assert actions == [:cancel]
    end

    # Regression: QueueItem.progress is already a 0..100 percentage, so the
    # download description must not multiply by 100 again (the "2330%" bug).
    test "download description shows progress as a percentage without re-scaling" do
      {action, _next, _actions} =
        PursuitStatus.derive(
          pursuit(:active),
          unit(),
          target(:acquired),
          queue_item(:downloading, %{progress: 23.3, timeleft: "13m", download_client: "qBittorrent"})
        )

      assert action.description =~ "23%"
      refute action.description =~ "2330%"
    end

    test "queued -> Queued, cancel only" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(:queued))

      assert action.verb == "Queued"
      assert actions == [:cancel]
    end

    test "stalled -> Stalled (warning) with change_target + request_decision" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(:stalled))

      assert action.verb == "Stalled"
      assert action.severity == :warning
      assert :change_target in actions
      assert :request_decision in actions
    end

    test "post-processing states -> their own verbs, never 'unrecognized', never a crash" do
      # SABnzbd's post-download pipeline (verify → repair → unpack → move)
      # reports through these states. "Moving" in particular runs for
      # minutes on a large file crossing mounts — showing it as an
      # unrecognized state with a "change target" hint invites the user
      # to abandon a healthy download.
      for {state, verb} <- [
            {:verifying, "Verifying"},
            {:repairing, "Repairing"},
            {:extracting, "Unpacking"},
            {:moving, "Moving"}
          ] do
        {action, next, actions} =
          PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(state))

        assert action.verb == verb
        assert action.severity == :info
        assert action.description =~ "download client"
        assert next.description =~ "lands in the library"
        assert actions == [:cancel], "post-processing must not offer change_target"
      end
    end

    test "paused -> Paused" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(:paused))

      assert action.verb == "Paused"
      assert actions == [:cancel]
    end

    test "completed -> Verifying" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(:completed))

      assert action.verb == "Verifying"
      assert next.description =~ "InboundListener"
      assert actions == [:cancel]
    end

    test "error without a failure detail -> Failed with the generic description" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), queue_item(:error))

      assert action.verb == "Failed"
      assert action.severity == :error
      assert action.description == "Download client reported an error."
      assert next.description =~ "download client"
      assert :change_target in actions
    end

    test "error with a client failure message -> the client's own words, verbatim" do
      # SABnzbd's terminal failures ("Repair failed, not enough repair
      # blocks", "Unpacking failed") name the exact condition — the user
      # must see that, not a generic "reported an error".
      {action, next, actions} =
        PursuitStatus.derive(
          pursuit(:active),
          unit(),
          target(:acquired),
          queue_item(:error, %{
            download_client: "SABnzbd",
            failure_message: "Repair failed, not enough repair blocks"
          })
        )

      assert action.verb == "Failed"
      assert action.severity == :error
      assert action.description == "SABnzbd: Repair failed, not enough repair blocks"
      assert next.description =~ "different release"
      assert :change_target in actions
    end

    test "no queue match -> Downloaded with change_target hint" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), nil)

      assert action.verb == "Downloaded"
      assert :change_target in actions
    end
  end

  describe "derive/4 — location-aware post-download stage" do
    test "acquired + no queue + :in_review -> In review (no change_target)" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), nil, :in_review)

      assert action.verb == "In review"
      assert action.severity == :info
      assert next.description =~ "Review"
      assert actions == [:cancel]
    end

    test "acquired + no queue + :none -> Downloaded (delegates to derive/3)" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:active), unit(), target(:acquired), nil, :none)

      assert action.verb == "Downloaded"
      assert :change_target in actions
    end

    test "location is ignored once a queue item is present" do
      {action, _next, _actions} =
        PursuitStatus.derive(
          pursuit(:active),
          unit(),
          target(:acquired),
          queue_item(:downloading),
          :in_review
        )

      assert action.verb == "Downloading"
    end
  end

  describe "derive/3 — active + terminal-failure target states" do
    test "failed -> Stopped with change_target + request_decision" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), unit(), target(:failed), nil)

      assert action.verb == "Stopped"
      assert :change_target in actions
      assert :request_decision in actions
    end

    test "cancelled target -> Stopped with change_target" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), unit(), target(:cancelled), nil)

      assert action.verb == "Stopped"
      assert :change_target in actions
    end
  end

  describe "derive/3 — active + no target" do
    test "missing target -> Unknown with cancel + change_target" do
      {action, _next, actions} = PursuitStatus.derive(pursuit(:active), unit(), nil, nil)

      assert action.verb == "Unknown"
      assert action.severity == :warning
      assert :cancel in actions
      assert :change_target in actions
    end
  end

  describe "derive/3 — terminal pursuit states" do
    test "active + awaiting_decision_at -> Decision needed" do
      {action, _next, actions} =
        PursuitStatus.derive(
          pursuit(:active),
          unit(%{awaiting_decision_at: DateTime.utc_now(:second)}),
          target(:seeking),
          nil
        )

      assert action.verb == "Decision needed"
      assert actions == [:cancel]
    end

    test "satisfied -> Done, no actions, no next_step" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:satisfied), unit(%{state: "satisfied"}), target(:acquired), nil)

      assert action.verb == "Done"
      assert action.severity == :success
      assert next == nil
      assert actions == []
    end

    test "exhausted -> Gave up, no actions" do
      {action, _next, actions} =
        PursuitStatus.derive(pursuit(:exhausted), unit(%{state: "exhausted"}), target(:failed), nil)

      assert action.verb == "Gave up"
      assert action.severity == :error
      assert actions == []
    end

    test "cancelled -> Cancelled, no actions" do
      {action, next, actions} =
        PursuitStatus.derive(pursuit(:cancelled), unit(%{state: "cancelled"}), nil, nil)

      assert action.verb == "Cancelled"
      assert next == nil
      assert actions == []
    end
  end

  describe "compose_downloads/2 — composite download presentation (UIDR-029 follow-up)" do
    alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, DownloadProgress}

    defp entry(pct, title \\ "Sample.Show.S01E01.DVDRip.x264") do
      %{
        item_id: "qi-#{title}-#{pct}",
        download: %DownloadProgress{
          state: :downloading,
          progress_pct: pct,
          eta: "0:00:10",
          client: "SABnzbd"
        },
        release_title: title
      }
    end

    defp downloading_action do
      %CurrentAction{
        verb: "Downloading",
        description: "ETA 0:00:00 • 100% • From SABnzbd",
        severity: :info
      }
    end

    test "finished entries leave the list and are counted" do
      {_action, kept, done} =
        PursuitStatus.compose_downloads(downloading_action(), [
          entry(100.0, "Sample.Show.S01E01.x264"),
          entry(40.0, "Sample.Show.S01E02.x264"),
          entry(100.0, "Sample.Show.S01E03.x264")
        ])

      assert done == 2
      assert [%{release_title: "Sample.Show.S01E02.x264"}] = kept
    end

    test "a multi-file pursuit's header aggregates instead of narrating one file" do
      {action, _kept, _done} =
        PursuitStatus.compose_downloads(downloading_action(), [
          entry(100.0, "Sample.Show.S01E01.x264"),
          entry(40.0, "Sample.Show.S01E02.x264"),
          entry(0.0, "Sample.Show.S01E03.x264")
        ])

      assert action.description == "1 of 3 finished • From SABnzbd"
    end

    test "all finished reads as done, list empties" do
      {action, kept, done} =
        PursuitStatus.compose_downloads(downloading_action(), [
          entry(100.0, "Sample.Show.S01E01.x264"),
          entry(100.0, "Sample.Show.S01E02.x264")
        ])

      assert kept == []
      assert done == 2
      assert action.description == "2 of 2 finished • From SABnzbd"
    end

    test "a single-download pursuit keeps the per-file description untouched" do
      action = downloading_action()

      {composed, kept, done} =
        PursuitStatus.compose_downloads(action, [entry(40.0)])

      assert composed == action
      assert done == 0
      assert [_one] = kept

      # And a finished single download still empties the list without
      # rewriting the verb's description (the header already says it).
      {composed, kept, done} = PursuitStatus.compose_downloads(action, [entry(100.0)])
      assert composed == action
      assert kept == []
      assert done == 1
    end

    test "non-downloading actions never get rewritten" do
      action = %CurrentAction{verb: "Stalled", description: "No peers.", severity: :warning}

      {composed, _kept, _done} =
        PursuitStatus.compose_downloads(action, [entry(100.0, "a"), entry(50.0, "b")])

      assert composed == action
    end
  end

  describe "criteria_summary/1 — user-facing copy, never raw keys" do
    test "the per-title acceptance reads as words" do
      assert PursuitStatus.criteria_summary(%{"min_quality" => "any"}) == "lower quality accepted"
    end

    test "quality bounds read as words" do
      assert PursuitStatus.criteria_summary(%{"min_quality" => "hd_1080p"}) == "1080p or better"

      assert PursuitStatus.criteria_summary(%{"min_quality" => "any", "max_quality" => "hd_1080p"}) ==
               "lower quality accepted, up to 1080p"
    end

    test "empty or missing criteria summarize to nothing" do
      assert PursuitStatus.criteria_summary(nil) == nil
      assert PursuitStatus.criteria_summary(%{}) == nil
    end

    test "unknown keys fall back to key: value rather than disappearing" do
      assert PursuitStatus.criteria_summary(%{"weird" => "thing"}) == "weird: thing"
    end
  end
end
