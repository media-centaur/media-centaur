defmodule MediaCentarrWeb.LibraryFormatters do
  @moduledoc """
  Display-string helpers for library cards, status rows, and the playback-
  failure flash. Pure functions — no I/O, no assigns.
  """

  alias MediaCentarr.DateUtil

  # --- Duration ---

  def format_human_duration(seconds) when seconds >= 3600 do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if minutes > 0,
      do: "#{hours}h #{minutes}m",
      else: "#{hours}h"
  end

  def format_human_duration(seconds) when seconds >= 60 do
    "#{div(seconds, 60)}m"
  end

  def format_human_duration(_seconds), do: "< 1m"

  # --- Type and year ---

  def format_type(:movie), do: "Movie"
  def format_type(:movie_series), do: "Movie Series"
  def format_type(:tv_series), do: "TV Series"
  def format_type(:video_object), do: "Video"
  def format_type(type), do: type |> to_string() |> String.capitalize()

  def extract_year(date_string), do: DateUtil.extract_year(date_string) || ""

  # --- Playback failure flash ---

  @doc """
  Formats a user-facing flash message for a `:playback_failed` payload.

  Payload shape (built in `MediaCentarr.Playback.MpvSession`):
    - `message`        — short diagnostic derived from mpv stderr
    - `entity_name`    — e.g. "Sample Show" (nil → falls back to filename)
    - `season_number`  — integer or nil
    - `episode_number` — integer or nil
    - `content_url`    — absolute path

  The resulting string is two parts joined by " — ":
  the "Couldn't play X" heading, and the diagnostic. When the diagnostic
  suggests a missing file we append a storage-mount hint, since the most
  common root cause is a media drive that mounted after the app started.
  """
  @spec playback_failed_flash(map()) :: String.t()
  def playback_failed_flash(payload) do
    heading = failure_heading(payload)
    body = failure_body(payload[:message])
    "#{heading} — #{body}"
  end

  defp failure_heading(%{entity_name: name} = payload) when is_binary(name) and name != "" do
    "Couldn't play " <> name <> failure_episode_suffix(payload)
  end

  defp failure_heading(%{content_url: url}) when is_binary(url) do
    "Couldn't play " <> Path.basename(url)
  end

  defp failure_heading(_payload), do: "Couldn't play file"

  defp failure_episode_suffix(%{season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    " S#{season}E#{episode}"
  end

  defp failure_episode_suffix(_payload), do: ""

  defp failure_body(nil), do: "Unknown error."
  defp failure_body(""), do: "Unknown error."

  defp failure_body(message) when is_binary(message) do
    normalized = if String.ends_with?(message, [".", "!", "?"]), do: message, else: message <> "."
    maybe_append_storage_hint(normalized)
  end

  defp maybe_append_storage_hint(message) do
    if storage_hint?(message) do
      message <> " Check that your media drive is mounted."
    else
      message
    end
  end

  defp storage_hint?(message) do
    downcased = String.downcase(message)

    String.contains?(downcased, "no such file") or
      String.contains?(downcased, "input/output error")
  end
end
