defmodule MediaCentarrWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  defdelegate format_seconds(seconds), to: MediaCentarr.Format

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
  Cancels any pending timer stored in `timer_assign` and schedules `message`
  to be sent to `self()` after `delay_ms` milliseconds. Returns the socket
  with the new timer ref stored in `timer_assign`.

  Callers that need to accumulate data (e.g. LibraryLive's pending entity IDs)
  do so before calling this — the utility only manages the timer lifecycle.

  ## Examples

      # Simple debounce
      debounce(socket, :reload_timer, :reload_groups, 500)

      # With accumulation
      socket
      |> assign(pending_ids: MapSet.union(socket.assigns.pending_ids, new_ids))
      |> debounce(:reload_timer, :reload_entities, 500)
  """
  def debounce(socket, timer_assign, message, delay_ms) do
    if socket.assigns[timer_assign] do
      Process.cancel_timer(socket.assigns[timer_assign])
    end

    timer = Process.send_after(self(), message, delay_ms)
    assign(socket, [{timer_assign, timer}])
  end

  @doc """
  Applies a playback state change to a sessions map. On `:stopped`, removes
  the entity. On any other state, inserts or replaces the entry with the given
  `now_playing` data.

  Accepts an optional `extra_fields` map that is merged into the entry — used
  by StatusLive to preserve `started_at` timestamps that LibraryLive doesn't
  need.
  """
  def apply_playback_change(sessions, entity_id, new_state, now_playing, extra_fields \\ %{}) do
    case new_state do
      :stopped ->
        Map.delete(sessions, entity_id)

      _ ->
        entry = Map.merge(%{state: new_state, now_playing: now_playing}, extra_fields)
        Map.put(sessions, entity_id, entry)
    end
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
