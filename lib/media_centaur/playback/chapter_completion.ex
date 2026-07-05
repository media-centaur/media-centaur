defmodule MediaCentaur.Playback.ChapterCompletion do
  @moduledoc """
  Reads mpv chapter markers to find where a title's *content* ends, so
  playback completion can fire at the credits boundary instead of grinding
  through the tail to the position/eof fallback in `MpvSession`.

  ## Why chapters

  Completion otherwise triggers at `position / duration >= 0.90` (or true
  end-of-file). That fraction is of the *whole* file, credits included, so
  a title with a long credits tail marks the natural ending well before
  90% — the user finishes the story but the item isn't recorded as watched
  until they sit through the credits. A chapter that demarcates the credits
  is a per-file, tail-length-independent signal for "content is over."

  ## Detection is title-based and back-loaded on purpose

  We only treat a chapter as the content end when its title names it as
  credits/outro **and** it starts in the back stretch of the file
  (`@outro_floor`). Two false positives this guards against:

    * **Opening credits** — a chapter literally titled "Opening Credits"
      at `t=0` must never be read as the end. The back-stretch floor
      excludes it.
    * **Scene-marker chapters** — files chaptered every few minutes with
      generic titles ("Chapter 7") would let a purely structural
      "last chapter" rule complete *early* (e.g. at 82%), cutting off the
      climax. Requiring a credits title avoids that; untitled scene
      markers simply fall through to the existing 90%/eof path.

  Erring toward completing *late* (via the fallback) is the safe direction
  — marking a title watched before the user has seen the ending is worse
  than a few minutes' delay.
  """

  # A credits chapter must start at or after this fraction of the runtime.
  @outro_floor 0.80

  # Case-insensitive whole-word match. `credits` covers "End Credits",
  # "Closing Credits", "Credits"; `outro` covers "Outro". Deliberately
  # excludes bare "Ending" (often the story climax, not the credits).
  @credits_title ~r/\b(credits|outro)\b/i

  @doc """
  Returns the start time (seconds) of the credits chapter that marks the
  end of content, or `nil` when no such chapter is present.

  `chapters` is mpv's `chapter-list` payload — a list of maps carrying a
  `title` and a `time` (string or atom keys tolerated). When several
  chapters qualify, the earliest is returned (the true content end; any
  later "End Credits Song" split is still within the credits).
  """
  @spec content_end_seconds(list() | any(), number() | any()) :: number() | nil
  def content_end_seconds(chapters, duration)
      when is_list(chapters) and is_number(duration) and duration > 0 do
    floor_time = duration * @outro_floor

    chapters
    |> Enum.map(&normalize/1)
    |> Enum.filter(fn %{title: title, time: time} ->
      is_number(time) and time >= floor_time and credits_title?(title)
    end)
    |> case do
      [] -> nil
      matched -> matched |> Enum.map(& &1.time) |> Enum.min()
    end
  end

  def content_end_seconds(_chapters, _duration), do: nil

  defp normalize(chapter) when is_map(chapter) do
    %{
      title: Map.get(chapter, "title") || Map.get(chapter, :title),
      time: Map.get(chapter, "time") || Map.get(chapter, :time)
    }
  end

  defp normalize(_other), do: %{title: nil, time: nil}

  defp credits_title?(title) when is_binary(title), do: Regex.match?(@credits_title, title)
  defp credits_title?(_title), do: false
end
