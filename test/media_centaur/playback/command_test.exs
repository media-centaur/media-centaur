defmodule MediaCentaur.Playback.CommandTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.Command

  describe "ipc/2 — the mpv command a reader's command becomes" do
    test "pause toggles, seeks are relative, tracks are set by id or off" do
      assert Command.ipc(:toggle_pause, nil) == ["cycle", "pause"]
      assert Command.ipc({:seek, -10}, nil) == ["seek", -10, "relative"]
      assert Command.ipc({:seek, 60}, nil) == ["seek", 60, "relative"]
      assert Command.ipc({:select_track, :audio, 2}, nil) == ["set_property", "aid", 2]
      assert Command.ipc({:select_track, :subtitle, 3}, nil) == ["set_property", "sid", 3]
      assert Command.ipc({:select_track, :subtitle, :none}, nil) == ["set_property", "sid", "no"]
    end

    test "activating the prompt does what the prompt says, and nothing without one" do
      assert Command.ipc(:activate_prompt, {:skip_intro, 92.5}) == ["seek", 92.5, "absolute"]
      assert Command.ipc(:activate_prompt, :next_episode) == ["playlist-next"]
      assert Command.ipc(:activate_prompt, {:next_episode_in, 4}) == ["playlist-next"]
      assert Command.ipc(:activate_prompt, nil) == nil
    end
  end

  describe "valid?/1" do
    test "accepts the vocabulary and nothing else" do
      for command <- [
            :toggle_pause,
            {:seek, -10},
            :activate_prompt,
            {:select_track, :audio, 1},
            {:select_track, :subtitle, :none}
          ] do
        assert Command.valid?(command), inspect(command)
      end

      for command <- [:quit, {:seek, "ten"}, {:select_track, :video, 1}, ["cycle", "pause"]] do
        refute Command.valid?(command), inspect(command)
      end
    end
  end
end
