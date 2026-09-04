defmodule MediaCentaurWeb.Live.SettingsLive.ConnectionTest do
  @moduledoc """
  How old a connection-test result reads on the Settings page.

  A connection test is a point-in-time observation — a success a week ago
  doesn't tell you much about right now — so every place that shows one
  shows its age beside it. This module is that formatting, and nothing
  else: pure, `async: true`, with an injectable clock.

  Storing and reading the result is `MediaCentaur.Capabilities`
  (`load_test_result/1`, `save_test_result/2`), which also owns its key
  and its shape. This module used to carry a parallel `parse/1`,
  `serialize/1` and `storage_key/1` from before that move; they outlived
  their callers and are gone (audit E49).
  """

  @doc """
  Returns a human-readable age like `"just now"`, `"3 min ago"`,
  `"2 hours ago"`, `"5 days ago"`. The `now` argument is injectable for
  deterministic testing.
  """
  @spec relative_age(DateTime.t(), DateTime.t()) :: String.t()
  def relative_age(tested_at, now \\ DateTime.utc_now()) do
    tested_at
    |> then(&DateTime.diff(now, &1, :second))
    |> do_age()
  end

  defp do_age(seconds) when seconds < 60, do: "just now"

  defp do_age(seconds) when seconds < 3600 do
    minutes = div(seconds, 60)
    "#{minutes} #{pluralize(minutes, "min", "min")} ago"
  end

  defp do_age(seconds) when seconds < 86_400 do
    hours = div(seconds, 3600)
    "#{hours} #{pluralize(hours, "hour", "hours")} ago"
  end

  defp do_age(seconds) do
    days = div(seconds, 86_400)
    "#{days} #{pluralize(days, "day", "days")} ago"
  end

  defp pluralize(1, singular, _plural), do: singular
  defp pluralize(_, _singular, plural), do: plural
end
