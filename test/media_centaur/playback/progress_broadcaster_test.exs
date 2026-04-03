defmodule MediaCentaur.Playback.ProgressBroadcasterTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Playback.ProgressBroadcaster

  describe "broadcast/3" do
    test "broadcasts entity_progress_updated for entity with progress" do
      tv_series = create_entity(%{type: :tv_series, name: "Broadcast Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot",
          content_url: "/tv/show/s01e01.mkv"
        })

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 600.0,
        duration_seconds: 2400.0
      })

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      ProgressBroadcaster.broadcast(tv_series.id, 1, 1)

      assert_receive {:entity_progress_updated,
                      %{
                        entity_id: entity_id,
                        summary: summary
                      }}

      assert entity_id == tv_series.id
      assert is_map(summary)
    end

    test "returns :ok for nonexistent entity" do
      assert :ok == ProgressBroadcaster.broadcast(Ecto.UUID.generate(), 0, 0)
    end
  end
end
