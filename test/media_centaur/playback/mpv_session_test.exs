defmodule MediaCentaur.Playback.MpvSessionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.{Entry, Events, MpvProperties, MpvSession, WatchingTracker}

  defp entry(fields), do: struct!(%Entry{entity_id: "entity", content_url: "/media/a.mkv"}, fields)

  describe "reset_for_file/2" do
    @next_entry %Entry{
      entity_id: "entity",
      episode_id: "ep-2",
      season_number: 1,
      episode_number: 2,
      episode_name: "Sample Episode",
      content_url: "/media/b.mkv"
    }

    test "an episode advance keeps the profile the session was started for" do
      profile_id = Ecto.UUID.generate()

      state =
        struct!(MpvSession, %{
          profile_id: profile_id,
          entry: entry(episode_id: "ep-1"),
          properties: %MpvProperties{position: 1200.0},
          tracker: WatchingTracker.new()
        })

      next = MpvSession.reset_for_file(state, @next_entry)

      assert next.profile_id == profile_id
      assert next.entry.episode_id == "ep-2"
      assert next.entry.content_url == "/media/b.mkv"
      assert next.properties.position == 0.0
    end

    test "an advance keeps the selected tracks: mpv keeps them across files and reports only a change" do
      state =
        struct!(MpvSession, %{
          profile_id: Ecto.UUID.generate(),
          entry: entry(episode_id: "ep-1"),
          properties: %MpvProperties{aid: 1, sid: 2},
          tracker: WatchingTracker.new()
        })

      next = MpvSession.reset_for_file(state, @next_entry)

      assert next.properties.aid == 1
      assert next.properties.sid == 2
      assert next.enforced_sid == nil
    end
  end

  describe "session_ended/1" do
    test "names the session's entity, profile and completed set" do
      profile_id = Ecto.UUID.generate()

      state =
        struct!(MpvSession, %{
          entry: entry(entity_id: "movie-1", movie_id: "movie-1"),
          profile_id: profile_id,
          completed: MapSet.new([{:movie, "movie-1"}])
        })

      assert %Events.SessionEnded{entity_id: "movie-1", profile_id: ^profile_id, completed: completed} =
               MpvSession.session_ended(state)

      assert MapSet.equal?(completed, MapSet.new([{:movie, "movie-1"}]))
    end
  end
end
