defmodule MediaCentaur.Playback.Completion do
  @moduledoc """
  When a viewing is complete: the one judgment `MpvSession` applies to
  every position it persists (`reason/4`). A viewing is complete once the
  position reaches the **content end** — where the story stops and the
  credits begin (`content_end_seconds/3`).

  The content end comes from the best source the file offers:

    * a credits/outro chapter — measured, per file, independent of how
      long the credits run; otherwise
    * an estimate: the duration less the **assumed credits length**, which
      is 10% of the duration capped at 8 minutes for a movie and 3 minutes
      for anything else (an episode, an extra, a standalone video).

  ## Why the assumed credits length is capped

  Credits do not grow with the runtime. Without the cap a 156-minute film
  completes with 15 minutes left — before its final scene. With it, every
  file up to 80 minutes (episodes) or 30 minutes (anything else) keeps the
  plain 10% tail, and a long film completes once the last 8 minutes remain.
  A movie gets the longer cap because feature credits run 5–10 minutes; an
  episode's run 1–2, plus a preview of the next one.

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
      markers simply fall through to the estimate.

  Erring toward completing *late* is the safe direction — marking a title
  watched before the user has seen the ending is worse than a few
  minutes' delay, and completion is what offers the finish prompt's
  Delete.
  """

  alias MediaCentaur.Format

  # A credits chapter must start at or after this fraction of the runtime.
  @outro_floor 0.80

  # Without a credits chapter, the credits are assumed to run this
  # fraction of the runtime, up to the playable kind's cap.
  @credits_fraction 0.10
  @movie_credits_cap_seconds 480
  @credits_cap_seconds 180

  # Case-insensitive whole-word match. `credits` covers "End Credits",
  # "Closing Credits", "Credits"; `outro` covers "Outro". Deliberately
  # excludes bare "Ending" (often the story climax, not the credits).
  @credits_title ~r/\b(credits|outro)\b/i
  @credits_words ["credits", "outro"]

  @doc "The words a credits chapter title carries, lower case; `next_episode.lua` keeps the same list."
  @spec credits_words() :: [String.t()]
  def credits_words, do: @credits_words

  @doc "The fraction of the runtime a credits chapter must start at or after."
  @spec outro_floor() :: float()
  def outro_floor, do: @outro_floor

  @doc "Whether one `chapter-list` entry is the credits: a credits title starting at or after the outro floor of `duration`."
  @spec credits_chapter?(map(), number()) :: boolean()
  def credits_chapter?(chapter, duration)
      when is_map(chapter) and is_number(duration) and duration > 0 do
    %{title: title, time: time} = normalize(chapter)
    is_number(time) and time >= duration * @outro_floor and credits_title?(title)
  end

  def credits_chapter?(_chapter, _duration), do: false

  @doc """
  Why a viewing at `position` of `duration` (seconds) is complete — a
  human-readable reason for the log — or `nil` while it is not. `kind` is
  the playable's kind (`Entry.item/1`'s first element), nil for a file the
  library does not know.
  """
  @spec reason(number() | nil, number() | nil, list() | nil, atom() | nil) :: String.t() | nil
  def reason(position, duration, chapters, kind)
      when is_number(position) and is_number(duration) and duration > 0 do
    case credits_chapter_start(chapters, duration) do
      nil ->
        content_end = estimated_content_end(duration, kind)

        if position >= content_end,
          do:
            "#{Format.format_seconds(position)} reached estimated credits start at #{Format.format_seconds(content_end)} of #{Format.format_seconds(duration)}"

      chapter_start ->
        if position >= chapter_start,
          do: "reached credits chapter at #{Format.format_seconds(chapter_start)}"
    end
  end

  def reason(_position, _duration, _chapters, _kind), do: nil

  @doc """
  The content end (seconds) of a file of `duration` playing a `kind`
  playable: the start of its credits chapter, or the estimate when it has
  none. `nil` while the duration is unknown.

  `chapters` is mpv's `chapter-list` payload — a list of maps carrying a
  `title` and a `time` (string or atom keys tolerated). When several
  chapters qualify, the earliest is the content end (any later "End
  Credits Song" split is still within the credits).
  """
  @spec content_end_seconds(list() | nil, number() | nil, atom() | nil) :: number() | nil
  def content_end_seconds(chapters, duration, kind) when is_number(duration) and duration > 0,
    do: credits_chapter_start(chapters, duration) || estimated_content_end(duration, kind)

  def content_end_seconds(_chapters, _duration, _kind), do: nil

  defp credits_chapter_start(chapters, duration) when is_list(chapters) do
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

  defp credits_chapter_start(_chapters, _duration), do: nil

  defp estimated_content_end(duration, kind),
    do: duration - min(duration * @credits_fraction, credits_cap_seconds(kind))

  defp credits_cap_seconds(:movie), do: @movie_credits_cap_seconds
  defp credits_cap_seconds(_kind), do: @credits_cap_seconds

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
