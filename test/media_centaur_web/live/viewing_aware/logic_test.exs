defmodule MediaCentaurWeb.Live.ViewingAware.LogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Viewing
  alias MediaCentaurWeb.Live.ViewingAware.Logic

  describe "command_from_params/1 — the page's event payload as a Playback.Command" do
    test "pause, seeks and the prompt" do
      assert Logic.command_from_params(%{"command" => "toggle_pause"}) == {:ok, :toggle_pause}
      assert Logic.command_from_params(%{"command" => "seek", "seconds" => "-10"}) == {:ok, {:seek, -10}}
      assert Logic.command_from_params(%{"command" => "seek", "seconds" => 60}) == {:ok, {:seek, 60}}
      assert Logic.command_from_params(%{"command" => "prompt"}) == {:ok, :activate_prompt}
    end

    test "anything else is refused" do
      assert Logic.command_from_params(%{"command" => "quit"}) == :error
      assert Logic.command_from_params(%{"command" => "seek", "seconds" => "ten"}) == :error
      assert Logic.command_from_params(%{}) == :error
    end
  end

  describe "track_from_params/1" do
    test "a track by kind and id, or none" do
      assert Logic.track_from_params(%{"kind" => "audio", "id" => "2"}) ==
               {:ok, {:select_track, :audio, 2}}

      assert Logic.track_from_params(%{"kind" => "subtitle", "id" => "3"}) ==
               {:ok, {:select_track, :subtitle, 3}}

      assert Logic.track_from_params(%{"kind" => "subtitle", "id" => "none"}) ==
               {:ok, {:select_track, :subtitle, :none}}

      assert Logic.track_from_params(%{"kind" => "video", "id" => "1"}) == :error
    end
  end

  describe "bar_shown?/2 — when the bar is on screen" do
    test "while paused, and while the show timer runs; hidden otherwise" do
      playing = %Viewing{
        player: "p",
        entity_id: "e",
        profile_id: "pr",
        content_url: "/a",
        state: :playing
      }

      paused = %{playing | state: :paused}
      assert Logic.bar_shown?(paused, false)
      assert Logic.bar_shown?(playing, true)
      refute Logic.bar_shown?(playing, false)
    end
  end
end
