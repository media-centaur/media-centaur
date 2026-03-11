defmodule MediaCentaur.Playback.ProgressBroadcasterTest do
  use MediaCentaur.DataCase

  alias MediaCentaur.Playback.ProgressBroadcaster

  describe "broadcast/3" do
    test "broadcasts entity_progress_updated for entity with progress" do
      entity = create_entity(%{type: :tv_series, name: "Broadcast Show"})

      create_watch_progress(%{
        entity_id: entity.id,
        season_number: 1,
        episode_number: 1,
        position_seconds: 600.0,
        duration_seconds: 2400.0
      })

      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.playback_events())

      ProgressBroadcaster.broadcast(entity.id, 1, 1)

      assert_receive {:entity_progress_updated, entity_id, summary, _resume, _delta,
                      progress_records, _timestamp}

      assert entity_id == entity.id
      assert is_map(summary)
      assert is_list(progress_records)
      assert length(progress_records) == 1
    end

    test "returns :ok for nonexistent entity" do
      assert :ok == ProgressBroadcaster.broadcast(Ash.UUID.generate(), 0, 0)
    end
  end
end
