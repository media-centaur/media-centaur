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
end
