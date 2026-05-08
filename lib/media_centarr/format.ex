defmodule MediaCentarr.Format do
  @moduledoc """
  Shared formatting helpers for log messages and display.
  """
  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc """
  Formats a number of seconds into a human-readable duration string.

  Returns `"H:MM:SS"` when the duration is an hour or longer, otherwise `"M:SS"`.
  Returns `"0:00"` for nil.
  """
  def format_seconds(nil), do: "0:00"

  def format_seconds(seconds) when is_number(seconds) do
    total = trunc(seconds)
    hours = div(total, 3600)
    mins = div(rem(total, 3600), 60)
    secs = rem(total, 60)
    pad_secs = String.pad_leading(Integer.to_string(secs), 2, "0")

    if hours > 0 do
      "#{hours}:#{String.pad_leading(Integer.to_string(mins), 2, "0")}:#{pad_secs}"
    else
      "#{mins}:#{pad_secs}"
    end
  end

  @doc """
  Returns the first 8 characters of a UUID for log readability.
  """
  def short_id(uuid) when is_binary(uuid), do: String.slice(uuid, 0, 8)

  @doc """
  Zero-pads a non-negative integer to two digits.

      iex> MediaCentarr.Format.pad2(3)
      "03"
      iex> MediaCentarr.Format.pad2(42)
      "42"
  """
  @spec pad2(non_neg_integer()) :: String.t()
  def pad2(n) when is_integer(n) and n >= 0 and n < 10, do: "0" <> Integer.to_string(n)
  def pad2(n) when is_integer(n) and n >= 0, do: Integer.to_string(n)

  @doc """
  Renders an `SnnEnn` episode label from a season + episode pair. Returns
  `"Season N"` for season-pack pairs (episode is nil) and `""` when both
  are nil.

      iex> MediaCentarr.Format.episode_label(1, 3)
      "S01E03"
      iex> MediaCentarr.Format.episode_label(2, nil)
      "Season 2"
      iex> MediaCentarr.Format.episode_label(nil, nil)
      ""
  """
  @spec episode_label(integer() | nil, integer() | nil) :: String.t()
  def episode_label(nil, nil), do: ""
  def episode_label(season, nil) when is_integer(season), do: "Season #{season}"

  def episode_label(season, episode) when is_integer(season) and is_integer(episode),
    do: "S#{pad2(season)}E#{pad2(episode)}"

  @doc """
  Formats a `DateTime` as a relative ago string with minute-level resolution.
  Used by activity-zone surfaces where seconds-precision is meaningful.

      iex> dt = DateTime.add(DateTime.utc_now(), -90, :second)
      iex> MediaCentarr.Format.relative_ago(dt)
      "1m ago"
  """
  @spec relative_ago(DateTime.t() | nil) :: String.t()
  def relative_ago(nil), do: "never"

  def relative_ago(%DateTime{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  @doc """
  Formats a `DateTime` as a relative ago string with `"just now"` granularity.
  Used by pursuit timeline rows where sub-minute precision is noise.

      iex> dt = DateTime.add(DateTime.utc_now(), -10, :second)
      iex> MediaCentarr.Format.relative_just_now(dt)
      "just now"
  """
  @spec relative_just_now(DateTime.t()) :: String.t()
  def relative_just_now(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(:second), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
