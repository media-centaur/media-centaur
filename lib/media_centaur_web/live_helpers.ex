defmodule MediaCentaurWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

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
  Debounces a stats refresh by cancelling any pending timer and scheduling a new
  `:refresh_stats` message after 1 second.

  Expects the socket to have a `:stats_timer` assign.
  """
  def debounce_stats_refresh(socket) do
    if socket.assigns[:stats_timer] do
      Process.cancel_timer(socket.assigns.stats_timer)
    end

    timer = Process.send_after(self(), :refresh_stats, 1_000)
    assign(socket, stats_timer: timer)
  end
end
