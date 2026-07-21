defmodule MediaCentaurWeb.LiveHelpers do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  defdelegate format_seconds(seconds), to: MediaCentaur.Format

  @doc """
  Converts a param string to an already-interned atom, returning `default`
  (nil unless given) for anything unrecognized rather than raising.

  Use this for every param→atom conversion in `handle_event` — raw
  `String.to_existing_atom/1` on user-controlled params raises
  `ArgumentError` on a stray `phx-value`. Pass a domain default for the
  forgiving case, or use the nil default and guard the result for the
  reject-unknown case.
  """
  @spec safe_existing_atom(String.t(), atom()) :: atom()
  def safe_existing_atom(value, default \\ nil) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> default
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
  Formats the elapsed time since a `DateTime` as a bare duration —
  "<1s", "42s", "3m", "2h" — for copy that supplies its own preposition
  ("offline for 3m", "down 2h"). Contrast `time_ago/1`, which appends
  "ago".
  """
  @spec duration_since(DateTime.t()) :: String.t()
  def duration_since(%DateTime{} = since) do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), since, :millisecond)

    cond do
      elapsed_ms < 1_000 -> "<1s"
      elapsed_ms < 60_000 -> "#{div(elapsed_ms, 1_000)}s"
      elapsed_ms < 3_600_000 -> "#{div(elapsed_ms, 60_000)}m"
      true -> "#{div(elapsed_ms, 3_600_000)}h"
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
    # Within 30 days, reuse the shared relative-ago ladder ("just now"
    # granularity); older entries collapse to a short calendar date.
    if DateTime.diff(DateTime.utc_now(), datetime, :second) < 30 * 86_400 do
      MediaCentaur.Format.relative_ago(datetime, sub_minute: :just_now)
    else
      Calendar.strftime(datetime, "%b %d")
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
      MediaCentaur.Library.Image.web_path(image.content_url) <> cache_bust(image)
    end
  end

  @doc """
  Appends a `?w=<width>` hint to a local `/media-images/...` URL so
  `ImageServer` serves a width-constrained derivative instead of the
  full-resolution master.

  Use for artwork shown in a small box (calendar tiles, grid thumbnails,
  poster rows) where decoding the full master would needlessly block paint.
  Size the width to the rendered box × the target device-pixel-ratio (≈2×)
  so the source stays crisp on high-DPI / 4K displays. **Omit it entirely**
  for full-bleed / hero / detail-modal backdrops — those must keep the master
  to render sharply at full-viewport scale.

  Only local `/media-images/...` URLs are tagged — ImageServer can't resize a
  remote TMDB URL, so any other value (remote URL, `nil`) passes through
  unchanged, making this safe to apply at any call site. Preserves an existing
  query string (e.g. a `?v=` cache-buster).
  """
  def sized_image_url("/media-images/" <> _ = url, width) when is_integer(width) and width > 0 do
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    "#{url}#{separator}w=#{width}"
  end

  def sized_image_url(url, _width), do: url

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
  Release/file size for display — decimal units (GB/MB), the indexer
  convention. Thin delegate to `MediaCentaur.Format.format_size_decimal/1`;
  kept here so the many web call sites can `import` it locally.
  """
  defdelegate format_size(bytes), to: MediaCentaur.Format, as: :format_size_decimal

  @doc """
  Stable per-title hue for synthetic identity banners (UIDR-014) — the
  same title always lands the same tint. Chroma stays low in the CSS;
  the scrim rule keeps semantic colors the brightest accents.
  """
  def banner_hue(title), do: :erlang.phash2(title, 360)

  @doc """
  Resolves one delete button's gesture state for `target` — any sum
  type identifying what a click targets (the entity detail page uses
  `:all | {:file, path} | {:folder, path}`; Review uses `{:file, path} |
  {:folder, path}`). The lifecycle is `:idle → :confirm → :deleting`:

    * `:deleting` — an async/in-flight delete is running for this
      target (`deleting == target`); the button shows "Deleting…".
    * `:confirm` — armed, awaiting the second click
      (`delete_confirm == target`); the button shows "Click again…".
    * `:idle` — neither.

  `:deleting` outranks `:confirm` so a button can't claim both at once.
  Pure — shared by every host that implements the click-to-confirm
  delete gesture (ADR-030: extracted so the label/disabled logic is
  unit tested without rendering), rather than each host reimplementing
  its own copy of this state machine.
  """
  @spec delete_gesture_state(term(), term(), term()) :: :idle | :confirm | :deleting
  def delete_gesture_state(target, deleting, delete_confirm) do
    cond do
      deleting == target -> :deleting
      delete_confirm == target -> :confirm
      true -> :idle
    end
  end

  @doc """
  True while any delete is in flight for the host's `deleting` assign.
  Every delete button disables during it so a second destructive op
  can't be stacked on the busy view.
  """
  @spec delete_in_flight?(term()) :: boolean()
  def delete_in_flight?(deleting), do: deleting != nil
end
