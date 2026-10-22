defmodule MediaCentaur.Playback.IntroChapter do
  @moduledoc """
  The chapter titles Skip Intro answers to, and where it seeks.

  The desktop's mpv draws its own Skip Intro pill from `skip_intro.lua` in
  the bundled package (ADR-072), which runs inside that process. A remote
  player draws nothing (`campaigns/remote-players.md`, M5), so the host
  judges the same rule here and the page draws the prompt. The two word
  lists are held equal by `chapter_words_lua_sync_test.exs`.

  A title is an intro when it is, or starts with, one of `words/0` as a
  whole word (`Intro`, `Intro Song`, `Opening Credits`, `OP 2`, `OP2`,
  `Prologue`), case-insensitively. `Introduction` and `Open Water` are not.
  """

  @words ["intro", "opening", "op", "prologue"]
  @intro_title ~r/^(intro|opening|op)(\s|\d|$)|^prologue$/i

  @doc "The words, lower case, in the Lua package's order."
  @spec words() :: [String.t()]
  def words, do: @words

  @doc "Whether a chapter title names an intro."
  @spec intro?(String.t() | nil) :: boolean()
  def intro?(title) when is_binary(title), do: Regex.match?(@intro_title, title)
  def intro?(_title), do: false

  @doc """
  The start time of the chapter after the intro chapter at `index` in mpv's
  `chapter-list`, or nil: no current chapter, not an intro, or the intro is
  the last chapter (nowhere to skip to).
  """
  @spec skip_target([map()], integer() | nil) :: number() | nil
  def skip_target(chapters, index) when is_list(chapters) and is_integer(index) and index >= 0 do
    with %{} = current <- Enum.at(chapters, index),
         true <- intro?(title_of(current)),
         %{} = next <- Enum.at(chapters, index + 1) do
      time_of(next)
    else
      _other -> nil
    end
  end

  def skip_target(_chapters, _index), do: nil

  defp title_of(chapter), do: Map.get(chapter, "title") || Map.get(chapter, :title)
  defp time_of(chapter), do: Map.get(chapter, "time") || Map.get(chapter, :time)
end
