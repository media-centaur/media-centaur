defmodule MediaCentaurWeb.IncomingLive.View do
  @moduledoc """
  The Incoming page's one composition point (ADR-030 applied at page scale).

  Every section of the page is a projection of the same story — a wanted
  title moving from the watchlist (its next release) through pursuit (in
  flight) to outcome (ledger) — so the sections are built together, from
  one set of injected facts, by one pure function. The LiveView holds a
  single `%View{}` assign instead of two pages' worth of loose section
  state.

  Honest degradation is enforced here and only here, on two distinct gates:
  `prowlarr_ready?` (no indexer ⇒ the operational sections come back empty)
  and `acquisition_ready?` (indexer + download client ⇒ only then may a
  row's next release claim `:armed`/`:in_pursuit`), regardless of what the
  caller passes. Templates never re-check capabilities per section.

  Deliberately NOT composed here: live queue pairing. `QueueMatcher.match/2`
  runs at render time (see the render-time pairing note in the page module)
  so DB-backed sections don't rebuild on every queue snapshot;
  `with_progress/2` is the pure bridge that stamps paired percentages onto
  in-pursuit watchlist rows during that same render pass.

  The page's `build_view/1` is its single rebuild path and, by decision,
  carries the watchlist reads (the intents, their social activity,
  acquisition states and posters) on every rebuild alongside the forecast
  — ADR-030 at page scale: one composition point over one set of fresh
  facts, with that read cost accepted rather than a second, partial path.
  """

  alias MediaCentaur.Acquisition.ViewModels.PursuitRow
  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaurWeb.Components.Title.Row.NextRelease
  alias MediaCentaurWeb.IncomingLive.View
  alias MediaCentaurWeb.IncomingLive.WatchlistRows

  defstruct watchlist: [], in_flight: [], drafts: []

  @type t :: %View{
          watchlist: [WatchlistRows.row()],
          in_flight: [PursuitRow.t()],
          drafts: [map()]
        }

  @doc """
  Build the page view from already-read facts:

    * `:releases` — the `ReleaseTracking` read (items preloaded)
    * `:watchlist` — the `Discovery.list_watchlist/0` read
    * `:social_activity` — `Activities.activity_for/1` for the watchlist's refs
    * `:acquisition_states` — `TitleStates.for_refs/1` for the same refs
    * `:posters` — `ref => poster url` for the same refs
    * `:pursuit_rows` / `:drafts` — acquisition reads (the History
      archive reads separately via `compute_history_rows`)
    * `:today`, `:acquisition_ready?`, `:approval_policy`,
      `:grab_status_by_key` — the `UpcomingFeed` context facts
  """
  @spec build(map()) :: t()
  def build(inputs) do
    feed = UpcomingFeed.build(inputs.releases, feed_context(inputs))

    %View{
      watchlist:
        WatchlistRows.build(%{
          watchlist: inputs.watchlist,
          feed: feed,
          social_activity: inputs.social_activity,
          acquisition_states: inputs.acquisition_states,
          posters: inputs.posters,
          today: inputs.today
        }),
      in_flight: if(inputs.prowlarr_ready?, do: inputs.pursuit_rows, else: []),
      drafts: if(inputs.prowlarr_ready?, do: inputs.drafts, else: [])
    }
  end

  @doc """
  Stamp live download percentages onto in-pursuit rows —
  `%{pursuit_id => percent}` comes from the render-time queue pairing. A
  row whose pursuit has no paired torrent yet (still searching the
  indexers) stays percentless.
  """
  @spec with_progress([WatchlistRows.row()], %{optional(Ecto.UUID.t()) => non_neg_integer()}) ::
          [WatchlistRows.row()]
  def with_progress(rows, progress_by_pursuit) do
    Enum.map(rows, fn
      %{next_release: %NextRelease{status: :in_pursuit, pursuit_id: id} = next} = row
      when is_binary(id) ->
        %{row | next_release: %{next | percent: Map.get(progress_by_pursuit, id)}}

      row ->
        row
    end)
  end

  defp feed_context(inputs) do
    %{
      today: inputs.today,
      acquisition_ready?: inputs.acquisition_ready?,
      approval_policy: inputs.approval_policy,
      rungs: Map.get(inputs, :rungs, %{}),
      grab_status_by_key: if(inputs.acquisition_ready?, do: inputs.grab_status_by_key, else: %{})
    }
  end
end
