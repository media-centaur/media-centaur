defmodule MediaCentaurWeb.IncomingLive.View do
  @moduledoc """
  The Incoming page's one composition point (ADR-030 applied at page scale).

  Every section of the page is a projection of the same story — a wanted
  title moving from forecast (shelf) through pursuit (in flight) to outcome
  (ledger) — so the sections are built together, from one set of injected
  facts, by one pure function. The LiveView holds a single `%View{}` assign
  instead of two pages' worth of loose section state.

  Honest degradation is enforced here and only here, on two distinct gates:
  `prowlarr_ready?` (no indexer ⇒ the operational sections come back empty)
  and `acquisition_ready?` (indexer + download client ⇒ only then may the
  shelf claim `:armed`/`:in_pursuit`), regardless of what the caller passes.
  Templates never re-check capabilities per section.

  Deliberately NOT composed here: live queue pairing. `QueueMatcher.match/2`
  runs at render time (see the render-time pairing note in the page module)
  so DB-backed sections don't rebuild on every queue snapshot;
  `with_progress/2` is the pure bridge that stamps paired percentages onto
  in-pursuit shelf cards during that same render pass.
  """

  import MediaCentaurWeb.LiveHelpers, only: [sized_image_url: 2]

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.Incoming.Shelf.Card
  alias MediaCentaurWeb.IncomingLive.View

  @shelf_cap 6
  @shelf_art_width 342

  defstruct shelf: nil, in_flight: [], drafts: [], feed: %UpcomingFeed{}

  defmodule ShelfSection do
    @moduledoc """
    The Coming up shelf: capped dated cards, what the cap hides, and the
    tracked-but-unscheduled titles as rows of the same `Card` vocabulary
    (UIDR-017) — schedule state is a property of a row, not a class split.
    """
    defstruct cards: [], overflow_count: 0, stragglers: []

    @type t :: %__MODULE__{
            cards: [Card.t()],
            overflow_count: non_neg_integer(),
            stragglers: [Card.t()]
          }
  end

  @type t :: %View{
          shelf: ShelfSection.t(),
          in_flight: [PursuitRow.t()],
          drafts: [map()],
          feed: UpcomingFeed.t()
        }

  @doc """
  Build the page view from already-read facts:

    * `:releases` / `:watching_items` — `ReleaseTracking` reads (items preloaded)
    * `:pursuit_rows` / `:drafts` — acquisition reads (the History
      archive reads separately via `compute_history_rows`)
    * `:today`, `:acquisition_ready?`, `:auto_grab_default_mode`,
      `:grab_status_by_key` — the `UpcomingFeed` context facts
    * `:shelf_expanded?` — the shelf's "Show all" disclosure state

  The full `feed` rides along for per-title detail building.
  """
  @spec build(map()) :: t()
  def build(inputs) do
    feed = UpcomingFeed.build(inputs.releases, feed_context(inputs))
    shelf_cap = if Map.get(inputs, :shelf_expanded?, false), do: :all, else: @shelf_cap
    {events, overflow_count} = UpcomingFeed.shelf_items(feed, shelf_cap)

    %View{
      shelf: %ShelfSection{
        cards: Enum.map(events, &card_from_event(&1, inputs.today)),
        overflow_count: overflow_count,
        stragglers:
          inputs.watching_items |> UpcomingFeed.stragglers() |> Enum.map(&card_from_straggler/1)
      },
      in_flight: if(inputs.prowlarr_ready?, do: inputs.pursuit_rows, else: []),
      drafts: if(inputs.prowlarr_ready?, do: inputs.drafts, else: []),
      feed: feed
    }
  end

  @doc """
  Stamp live download percentages onto in-pursuit cards —
  `%{pursuit_id => percent}` comes from the render-time queue pairing. Cards
  whose pursuit has no paired torrent yet (still searching the indexers)
  stay percentless; the hairline simply doesn't render.
  """
  @spec with_progress([Card.t()], %{optional(Ecto.UUID.t()) => non_neg_integer()}) :: [Card.t()]
  def with_progress(cards, progress_by_pursuit) do
    Enum.map(cards, fn
      %Card{status: :in_pursuit, pursuit_id: pursuit_id} = card when not is_nil(pursuit_id) ->
        %{card | percent: Map.get(progress_by_pursuit, pursuit_id)}

      card ->
        card
    end)
  end

  defp feed_context(inputs) do
    %{
      today: inputs.today,
      acquisition_ready?: inputs.acquisition_ready?,
      auto_grab_default_mode: inputs.auto_grab_default_mode,
      grab_status_by_key: if(inputs.acquisition_ready?, do: inputs.grab_status_by_key, else: %{})
    }
  end

  defp card_from_event(%Event{} = event, today) do
    %Card{
      key: event.id,
      item_id: event.item_id,
      pursuit_id: event.pursuit_id,
      title: event.item_name,
      subtitle: subtitle_for(event),
      date_label: UpcomingFeed.shelf_date_label(event, today),
      status: pill_status(event.status),
      art_url: art_url(event),
      kind: event.kind,
      episode_count: event.episode_count
    }
  end

  # The Upcoming statuses and the pill union are distinct vocabularies on
  # purpose (forecast ≠ pursuit lifecycle); this is the one mapping between
  # them. `:unscheduled` never reaches the shelf (stragglers carry those).
  defp pill_status(:under_pursuit), do: :in_pursuit
  defp pill_status(:armed), do: :armed
  # A fallback date can't lead a title's shelf card (the earlier armed date
  # always sorts first and past armed dates are kept), but map it defensively.
  defp pill_status(:armed_fallback), do: :tracked
  defp pill_status(:theatrical_info), do: :in_theaters
  defp pill_status(:in_library), do: :landed
  defp pill_status(:upcoming), do: :tracked

  # A straggler is the same row vocabulary with schedule facts absent:
  # no date label (the shelf renders the muted em-dash), the media type
  # as the caption, and the neutral Tracked pill.
  defp card_from_straggler(%UpcomingFeed.Straggler{} = straggler) do
    %Card{
      key: "straggler-#{straggler.item_id}",
      item_id: straggler.item_id,
      title: straggler.name,
      subtitle: media_label(straggler.media_type),
      status: :tracked,
      art_url: straggler.backdrop_path && backdrop_art_url(straggler.backdrop_path),
      kind: :title
    }
  end

  defp media_label(:tv_series), do: "TV series"
  defp media_label(:movie), do: "Movie"

  defp subtitle_for(%Event{kind: :season_drop} = event), do: "S#{event.season_number}"

  defp subtitle_for(%Event{kind: :episode} = event) do
    code = episode_code(event)
    if event.title, do: "#{code} · “#{event.title}”", else: code
  end

  # A movie release's title is usually just the movie's name again — only a
  # genuinely distinct edition title ("Restored edition") earns the caption.
  defp subtitle_for(%Event{kind: :movie, title: title, item_name: title}), do: nil
  defp subtitle_for(%Event{kind: :movie} = event), do: event.title

  defp episode_code(%Event{season_number: season, episode_number: episode}) do
    "S#{pad(season)}E#{pad(episode)}"
  end

  defp pad(number), do: number |> to_string() |> String.pad_leading(2, "0")

  defp art_url(%Event{backdrop_path: nil}), do: nil
  defp art_url(%Event{backdrop_path: path}), do: backdrop_art_url(path)

  defp backdrop_art_url(path),
    do: sized_image_url(MediaCentaur.Library.Image.web_path(path), @shelf_art_width)
end
