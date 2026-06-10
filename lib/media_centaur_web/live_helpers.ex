defmodule MediaCentaurWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  defdelegate format_seconds(seconds), to: MediaCentaur.Format

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
  Snapshots the current `Playback.Sessions` registry as a map keyed by
  entity id. Used by every LiveView that renders live playback state
  (Home, Library, Status). Pair with `apply_playback_change/5` to keep
  the snapshot in sync via PubSub.
  """
  @spec load_playback_sessions() :: %{optional(String.t()) => map()}
  def load_playback_sessions do
    Map.new(MediaCentaur.Playback.Sessions.list(), fn session ->
      {session.entity_id, session}
    end)
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
    # `Map.get/2`, not `entity.images`: some projection leaf shapes
    # (e.g. `DetailItem.movie_entry_to_map/1` movie rows) omit the
    # `:images` key entirely. Dot-access raises `KeyError` on a missing
    # key — not the same as a `nil` value — which previously crashed the
    # whole detail-panel render. A render helper must tolerate a missing
    # optional key.
    image = Enum.find(Map.get(entity, :images) || [], &(&1.role == role))

    if image && image.content_url do
      "/media-images/#{image.content_url}#{cache_bust(image)}"
    end
  end

  # The artwork file is rewritten in place on a TMDB re-scrape (same
  # `<owner_id>/<role>.<ext>` path), so a bare URL would let the browser
  # serve stale bytes for up to an hour (ImageServer's unversioned
  # `max-age=3600`). Appending the image's `updated_at` — bumped by
  # `Library.upsert_image/2` on every replace — flips ImageServer to its
  # immutable/versioned branch and guarantees a refetch the moment the
  # detail view reloads after `entities_changed`.
  defp cache_bust(image) do
    case Map.get(image, :updated_at) do
      %DateTime{} = dt -> "?v=#{DateTime.to_unix(dt)}"
      _ -> ""
    end
  end

  @doc """
  Release/file size for display — decimal units (GB/MB), one decimal
  for GB, the indexer convention. Returns nil for nil so callers can
  `:if` on the result.
  """
  def format_size(nil), do: nil

  def format_size(bytes) when is_integer(bytes) and bytes >= 1_000_000_000 do
    "#{Float.round(bytes / 1_000_000_000, 1)} GB"
  end

  def format_size(bytes) when is_integer(bytes) and bytes >= 1_000_000 do
    "#{div(bytes, 1_000_000)} MB"
  end

  def format_size(bytes) when is_integer(bytes), do: "#{bytes} B"
end
