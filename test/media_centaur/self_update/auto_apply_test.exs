defmodule MediaCentaur.SelfUpdate.AutoApplyTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.SelfUpdate.AutoApply
  alias MediaCentaur.Topics

  describe "detection_action/2 (a new version was detected)" do
    test "ignores detection when auto-update is off" do
      assert AutoApply.detection_action(false, false) == :ignore
      assert AutoApply.detection_action(false, true) == :ignore
    end

    test "applies immediately when auto-update is on and nothing is playing" do
      assert AutoApply.detection_action(true, false) == :apply
    end

    test "defers when auto-update is on but something is playing" do
      assert AutoApply.detection_action(true, true) == :defer
    end
  end

  describe "resume_action/3 (playback stopped)" do
    test "holds when nothing was deferred" do
      assert AutoApply.resume_action(false, true, false) == :hold
    end

    test "holds a deferred update when auto-update was turned off" do
      assert AutoApply.resume_action(true, false, false) == :hold
    end

    test "holds while another session is still playing" do
      assert AutoApply.resume_action(true, true, true) == :hold
    end

    test "applies the deferred update once the screen is idle" do
      assert AutoApply.resume_action(true, true, false) == :apply
    end
  end

  describe "wiring (real PubSub boundary)" do
    setup do
      test_pid = self()

      opts = [
        name: :"auto_apply_test_#{System.unique_integer([:positive])}",
        auto_enabled_fun: fn -> true end,
        apply_fun: fn -> send(test_pid, :applied) end
      ]

      pid = start_supervised!({AutoApply, opts})
      %{pid: pid}
    end

    defp detect_update do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.self_update_status(),
        {:check_complete, {:update_available, %{version: "9.9.9"}}}
      )
    end

    defp playback(entity_id, state) do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.playback_events(),
        {:playback_state_changed, %{entity_id: entity_id, state: state}}
      )
    end

    test "applies when a version is detected and nothing is playing" do
      detect_update()
      assert_receive :applied, 500
    end

    test "defers while something is playing, then applies once it stops" do
      playback("episode-1", :playing)
      detect_update()
      refute_receive :applied, 200

      playback("episode-1", :stopped)
      assert_receive :applied, 500
    end

    test "keeps deferring while another session is still playing" do
      playback("episode-1", :playing)
      playback("episode-2", :playing)
      detect_update()
      refute_receive :applied, 200

      # One of two sessions ends — screen is not yet idle.
      playback("episode-1", :stopped)
      refute_receive :applied, 200

      # Last session ends — now it applies.
      playback("episode-2", :stopped)
      assert_receive :applied, 500
    end

    test "ignores up-to-date and error outcomes" do
      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.self_update_status(),
        {:check_complete, {:up_to_date, %{version: "1.0.0"}}}
      )

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.self_update_status(),
        {:check_complete, {:error, :not_found}}
      )

      refute_receive :applied, 200
    end
  end
end
