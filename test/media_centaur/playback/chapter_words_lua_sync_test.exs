defmodule MediaCentaur.Playback.ChapterWordsLuaSyncTest do
  @moduledoc """
  The chapter-title words exist twice on purpose: in Lua for the desktop's
  mpv (`priv/mpv/scripts/media-centaur/`, which runs inside that process)
  and in Elixir for the host (`Playback.IntroChapter`, `Playback.Completion`),
  which draws the same prompts for a remote player. This test holds the two
  equal, so a word added on one side fails here until the other follows.
  """

  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.{Completion, IntroChapter, LaunchFlags, Viewing}

  defp lua(file), do: File.read!(Path.join(LaunchFlags.bundled_scripts_dir(), file))

  defp lua_table(source, name) do
    [_, body] = Regex.run(~r/local #{name} = \{(.*?)\n\}/s, source)
    Enum.map(Regex.scan(~r/"([^"]*)"/, body), fn [_, pattern] -> pattern end)
  end

  test "skip_intro.lua's intro patterns and IntroChapter.words/0 name the same words" do
    patterns = lua_table(lua("skip_intro.lua"), "intro_patterns")

    lua_words =
      patterns
      |> Enum.map(fn pattern ->
        [_, word] = Regex.run(~r/^\^([a-z]+)/, pattern)
        word
      end)
      |> Enum.uniq()

    assert Enum.sort(lua_words) == Enum.sort(IntroChapter.words())
    for word <- IntroChapter.words(), do: assert("^#{word}$" in patterns, word)
  end

  test "next_episode.lua's credits patterns and Completion.credits_words/0 name the same words" do
    patterns = lua_table(lua("next_episode.lua"), "credits_patterns")
    assert Enum.sort(patterns) == Enum.sort(Enum.map(Completion.credits_words(), &"%f[%a]#{&1}%f[%A]"))
  end

  test "the outro floor and the countdown window are the same numbers on both sides" do
    source = lua("next_episode.lua")
    [_, floor] = Regex.run(~r/outro_floor\s*=\s*([0-9.]+)/, source)
    [_, window] = Regex.run(~r/countdown_window\s*=\s*(\d+)/, source)
    assert String.to_float(floor) == Completion.outro_floor()
    assert String.to_integer(window) == Viewing.countdown_window_seconds()
  end
end
