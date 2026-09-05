defmodule MediaCentaur.DiscoveryRows do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Enriched activity rows in the shape `DiscoveryLive` assigns — the
  `Activities.activity_row/0` plus the page's joins (poster, library
  owner, watchlist membership, acquisition state) — for the pure
  projection tests.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.TMDB.Title

  @doc "One enriched row; `nickname: nil` with `own?: false` is a former friend."
  def activity_row(overrides \\ %{}) do
    activity = Map.get(overrides, :activity, %{})
    tmdb_id = Map.get(activity, :tmdb_id, 777)
    media_type = Map.get(activity, :media_type, :movie)

    title =
      Title.new!(%{
        tmdb_id: tmdb_id,
        media_type: media_type,
        name: Map.get(activity, :name, "Sample Movie #{tmdb_id}")
      })

    %{
      activity:
        struct!(
          Activity,
          Map.merge(
            %{
              id:
                Map.get(
                  activity,
                  :id,
                  "activity-#{tmdb_id}-#{Map.get(activity, :kind, :recommendation)}"
                ),
              kind: :recommendation,
              sentiment: :like,
              note: nil,
              episode: nil,
              tmdb_id: tmdb_id,
              media_type: media_type,
              title: title,
              acted_at: ~U[2026-09-01 12:00:00Z]
            },
            Map.delete(activity, :name)
          )
        ),
      nickname: Map.get(overrides, :nickname, "Sample Friend"),
      own?: Map.get(overrides, :own?, false),
      poster_url: Map.get(overrides, :poster_url),
      library_owner_id: Map.get(overrides, :library_owner_id),
      on_watchlist?: Map.get(overrides, :on_watchlist?, false),
      acquisition_state: Map.get(overrides, :acquisition_state)
    }
  end
end
