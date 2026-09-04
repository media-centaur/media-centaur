defmodule MediaCentaur.Log.ComponentTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Log.Component

  describe "the component vocabulary" do
    test "app and framework components partition the known list" do
      assert Component.app() ++ Component.framework() == Component.all()
    end

    test "every known component has a chip class" do
      for component <- Component.all() do
        assert is_binary(Component.chip_class(component)),
               "#{inspect(component)} has no chip class"
      end
    end

    test "an unknown component still renders with a fallback chip class" do
      assert is_binary(Component.chip_class(:not_a_component))
    end
  end

  describe "context_for_path/1" do
    test "a nested context file resolves to its context directory" do
      assert Component.context_for_path("lib/media_centaur/release_tracking/wants.ex") ==
               "release_tracking"
    end

    test "a context's root module file resolves to the same context" do
      assert Component.context_for_path("lib/media_centaur/review.ex") == "review"
    end

    test "the web layer has no owning context" do
      assert Component.context_for_path("lib/media_centaur_web/live/library_live.ex") == nil
    end

    test "a file outside the app has no owning context" do
      assert Component.context_for_path("test/media_centaur/review_test.exs") == nil
    end
  end

  describe "for_module/1" do
    test "a context module resolves through its context" do
      assert Component.for_module(MediaCentaur.Watcher.Supervisor) == :watcher
      assert Component.for_module(MediaCentaur.ReleaseTracking.Refresher) == :acquisition
    end

    test "a crash and a deliberate log from one context agree" do
      # Both used to disagree: the crash table said :self_update and
      # :library while the code logged :system and :playback (audit E53).
      assert Component.for_module(MediaCentaur.SelfUpdate.Updater) ==
               Component.for_context("self_update")

      assert Component.for_module(MediaCentaur.WatchHistory.Recorder) ==
               Component.for_context("watch_history")
    end

    test "an acronym context still resolves" do
      assert Component.for_module(MediaCentaur.TMDB.Client) == :tmdb
    end

    test "a longer prefix wins over a shorter one" do
      assert Component.for_module(MediaCentaur.Settings) == :settings
      assert Component.for_module(MediaCentaur.Settings.Controls) == :playback
    end

    test "web modules map to the domain they display" do
      assert Component.for_module(MediaCentaurWeb.IncomingLive) == :acquisition
      assert Component.for_module(MediaCentaurWeb.ReviewLive) == :review
    end

    test "a module outside the app has no component" do
      assert Component.for_module(Phoenix.LiveView.Channel) == nil
      assert Component.for_module(:some_erlang_module) == nil
    end
  end

  describe "for_context/1" do
    test "a context that logs as itself" do
      assert Component.for_context("playback") == :playback
    end

    test "several contexts share one component when they are one subsystem to a reader" do
      assert Component.for_context("downloads") == :acquisition
      assert Component.for_context("search") == :acquisition
      assert Component.for_context("release_tracking") == :acquisition
    end

    test "watch history is playback's record, not the library's" do
      assert Component.for_context("watch_history") == :playback
    end

    test "an unmapped context has no required component" do
      assert Component.for_context("no_such_context") == nil
    end

    test "every mapped component is a known component" do
      for {context, component} <- Component.context_components() do
        assert component in Component.all(),
               "#{context} maps to #{inspect(component)}, which is not a known component"
      end
    end
  end
end
