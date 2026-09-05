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
      MediaCentaur.ImageFiles.web_path(image.content_url) <> cache_bust(image)
    end
  end

  @tmdb_cdn_widths ~w(w92 w154 w185 w300 w342 w500 w780 w1280 original)a

  @doc """
  The one builder for TMDB CDN hotlinks — the **browsing tier** of the
  artwork ladder: search-result thumbs, plan-modal imagery, and cast
  headshots, where nothing is downloaded because no durable reference
  to the title exists yet. Referenced identities resolve locally via
  `MediaCentaur.TmdbArtwork.urls/2` instead; library entities via
  `image_url/2`.

  `width` must be one of TMDB's fixed size classes
  (#{inspect(@tmdb_cdn_widths)}) — an unknown one raises, same policy
  as `sized_image_url/2`. `nil` paths stay `nil` so call sites can
  chain their placeholder fallbacks.
  """
  @spec tmdb_cdn_url(String.t() | nil, atom()) :: String.t() | nil
  def tmdb_cdn_url(path, width) when width in @tmdb_cdn_widths do
    case path do
      nil -> nil
      "/" <> _ = path -> "https://image.tmdb.org/t/p/#{width}#{path}"
    end
  end

  @doc """
  The `src` a title thumb paints: the local cached tier when
  `TmdbArtwork` holds the identity, the TMDB hotlink otherwise, nil when
  the title carries no poster path either. Filesystem-only (no DB), so
  hosts may call it at render time per row or once at load;
  `title_summary/1` sizes the result.
  """
  @spec title_poster_url(MediaCentaur.TMDB.Title.t()) :: String.t() | nil
  def title_poster_url(%MediaCentaur.TMDB.Title{} = title) do
    MediaCentaur.TmdbArtwork.urls(title.media_type, title.tmdb_id).poster_url ||
      tmdb_cdn_url(title.poster_path, :w92)
  end

  @typedoc """
  How wide the surface will actually paint a piece of artwork.

  A positive integer is a device-pixel width; `:full_bleed` means the
  surface spans the viewport and wants the untouched master.
  """
  @type display_width :: pos_integer() | :full_bleed

  @doc """
  Renders a local artwork URL at the width the surface will paint it.

  **Every `<img>` pointing at `/media-images/...` goes through this**, and the
  width is part of the request rather than an afterthought — MC0028 enforces
  it. Omitting a width used to mean "serve the master", which read identically
  to having forgotten one, so full-bleed backdrops and 40px poster thumbnails
  were written the same way and the thumbnails quietly decoded 3840px masters.

  Two forms:

    * a **positive integer** — appends `?w=<width>` so `ImageServer` serves a
      width-constrained derivative. Size it to the rendered box × the target
      device-pixel-ratio (≈2× — this app composes at 1920 CSS px and runs on
      4K panels), then let the server snap up to its width ladder. Over-asking
      is cheap: `ImageFiles.derivative/2` never upscales, so a width at or
      above the master's own returns the master.
    * `:full_bleed` — returns the URL **byte-identical**, for surfaces that
      span the viewport (the home hero backdrop, the detail modal's cinematic
      backdrop and its pinned replica, the library/incoming atmosphere bands).
      Byte-identity is load-bearing twice over: `ArtworkWarmup` prefetches the
      bare `backdrop_url` for each hero page, and the detail modal's
      orientation backing replicates the cinematic backdrop exactly (see
      `.orientation-backing` in app.css). Any decoration here breaks both.

  Only local `/media-images/...` URLs are tagged — ImageServer can't resize a
  remote TMDB URL, so any other value (remote URL, `nil`) passes through
  unchanged, making this safe to apply at any call site. Preserves an existing
  query string (e.g. a `?v=` cache-buster).

  Anything outside the width vocabulary raises: a silently ignored width is
  the exact failure this function exists to prevent.
  """
  @spec sized_image_url(String.t() | nil, display_width()) :: String.t() | nil
  def sized_image_url("/media-images/" <> _ = url, width) when is_integer(width) and width > 0 do
    separator = if String.contains?(url, "?"), do: "&", else: "?"
    "#{url}#{separator}w=#{width}"
  end

  def sized_image_url("/media-images/" <> _ = url, :full_bleed), do: url

  def sized_image_url(url, width)
      when (is_nil(url) or is_binary(url)) and
             ((is_integer(width) and width > 0) or width == :full_bleed), do: url

  # A 2:3 poster paints at `--card-poster-w` (170 CSS px, app.css), which is
  # 340 device px on a 4K panel — the app composes at 1920 CSS px and scales
  # 2×. 640 clears that with room for the grid's `1fr` growth, which can
  # stretch a card ~11% past the token before a column is added.
  @poster_width 640

  @doc """
  The `src` every 2:3 poster renders, at any size the poster token produces.

  One size means one derivative: the library grid and Home's Recently Added
  row paint the same box (`--card-poster-w`), so they must request the same
  bytes. They used to name their own widths — 640 and 480 — which put two
  copies of every poster on disk and guaranteed the Home row missed the
  cache, because `ArtworkWarmup` prefetches this function's output and only
  ever knew about one of them.

  Public because that warmup calls it. A hint that differs by so much as a
  query parameter is a cache miss and dead weight, so the surfaces and the
  prefetch share one definition rather than three copies of a number.
  """
  @spec poster_src(String.t() | nil) :: String.t() | nil
  def poster_src(poster_url), do: sized_image_url(poster_url, @poster_width)

  # The artwork file is rewritten in place on a TMDB re-scrape (same
  # `<owner_id>/<role>.<ext>` path), so a bare URL would let the browser
  # serve stale bytes for up to an hour (ImageServer's unversioned
  # `max-age=3600`). Appending the image's `updated_at` — bumped by
  # `Library.Images.upsert/2` on every replace — flips ImageServer to its
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
