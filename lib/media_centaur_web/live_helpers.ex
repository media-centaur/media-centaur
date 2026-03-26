defmodule MediaCentaurWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  defdelegate format_seconds(seconds), to: MediaCentaur.Format

  @doc """
  Formats an ISO 8601 duration string (e.g. `"PT3H48M"`) into a human-readable
  form like `"3h 48m"`. Returns `nil` for `nil` input.
  """
  def format_iso_duration(nil), do: nil

  def format_iso_duration("PT" <> rest) do
    {hours, rest} = parse_duration_component(rest, "H")
    {minutes, _rest} = parse_duration_component(rest, "M")

    case {hours, minutes} do
      {0, m} -> "#{m}m"
      {h, m} -> "#{h}h #{m}m"
    end
  end

  defp parse_duration_component(string, suffix) do
    case String.split(string, suffix, parts: 2) do
      [num, rest] -> {String.to_integer(num), rest}
      [rest] -> {0, rest}
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

  @doc """
  Formats a `DateTime` or `NaiveDateTime` as a relative time string.

  Returns "just now" for < 1 minute, "Xm ago" for < 1 hour, "Xh ago" for < 1 day,
  "Xd ago" for < 30 days, or a short date like "Mar 05" for older.
  """
  def time_ago(nil), do: ""

  def time_ago(%NaiveDateTime{} = naive) do
    naive |> DateTime.from_naive!("Etc/UTC") |> time_ago()
  end

  def time_ago(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      diff < 30 * 86_400 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  @doc """
  Resolves an entity image URL for a given role (e.g. "poster", "backdrop", "logo").

  Returns a path like `/media-images/<content_url>` for local images, the remote
  URL for external images, or `nil` if no image exists for that role.
  """
  def image_url(entity, role) do
    image = Enum.find(entity.images || [], &(&1.role == role))

    if image && image.content_url do
      "/media-images/#{image.content_url}"
    end
  end
end
