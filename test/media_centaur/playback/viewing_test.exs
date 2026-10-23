defmodule MediaCentaur.Playback.ViewingTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.{Entry, MpvSession}
  alias MediaCentaur.Playback.TrackResolver.Track
  alias MediaCentaur.Playback.Viewing

  @chapters [
    %{"title" => "Intro", "time" => 0.0},
    %{"title" => "Story", "time" => 90.0},
    %{"title" => "End Credits", "time" => 2400.0}
  ]

  defp viewing(overrides) do
    struct!(
      %Viewing{
        player: :host,
        entity_id: "entity",
        profile_id: "profile",
        entity_name: "Sample Show",
        season_number: 2,
        episode_number: 4,
        episode_name: "The Long Night",
        content_url: "/shows/a.mkv",
        position_seconds: 100.0,
        duration_seconds: 2600.0,
        state: :playing,
        chapters: @chapters,
        chapter: 1,
        audio_tracks: [],
        subtitle_tracks: [],
        aid: 1,
        sid: false,
        successor_queued?: false,
        subtitle_text: nil
      },
      overrides
    )
  end

  describe "from_session/1 — the session's state as a reader needs it" do
    test "carries the title words, the position, the tracks, the chapter and the subtitle line" do
      session = %MpvSession{
        player: "player-1",
        profile_id: "profile",
        entry: %Entry{
          entity_id: "entity",
          entity_name: "Sample Show",
          season_number: 2,
          episode_number: 4,
          episode_name: "The Long Night",
          content_url: "/shows/a.mkv"
        },
        position: 100.0,
        duration: 2600.0,
        paused: true,
        state: :paused,
        chapters: @chapters,
        chapter: 1,
        audio_tracks: [%Track{index: 1, lang: "eng", codec: "dts"}],
        subtitle_tracks: [%Track{index: 2, lang: "eng", codec: "hdmv_pgs_subtitle"}],
        current_aid: 1,
        current_sid: 2,
        pending_next: %Entry{entity_id: "entity", episode_id: "next", content_url: "/shows/b.mkv"},
        subtitle_text: "A line"
      }

      viewing = Viewing.from_session(session)

      assert %Viewing{
               player: "player-1",
               entity_id: "entity",
               profile_id: "profile",
               entity_name: "Sample Show",
               season_number: 2,
               episode_number: 4,
               episode_name: "The Long Night",
               content_url: "/shows/a.mkv",
               position_seconds: 100.0,
               duration_seconds: 2600.0,
               state: :paused,
               chapter: 1,
               aid: 1,
               sid: 2,
               successor_queued?: true,
               subtitle_text: "A line"
             } = viewing

      assert [%Track{index: 2}] = viewing.subtitle_tracks
      assert viewing.prompt == nil
    end

    test "a session with nothing queued and no subtitle line reads so" do
      session = %MpvSession{
        player: :host,
        profile_id: "p",
        entry: %Entry{entity_id: "e", content_url: "/a.mkv"},
        state: :playing
      }

      viewing = Viewing.from_session(session)
      refute viewing.successor_queued?
      assert viewing.subtitle_text == nil
      assert viewing.prompt == nil
    end
  end

  describe "prompt/1 — Skip Intro and Next Episode, the desktop package's rules" do
    test "Skip Intro while an intro chapter plays and a chapter follows it" do
      assert Viewing.prompt(viewing(chapter: 0, position_seconds: 10.0)) == {:skip_intro, 90.0}
    end

    test "no Skip Intro outside the intro chapter" do
      assert Viewing.prompt(viewing(chapter: 1)) == nil
      assert Viewing.prompt(viewing(chapter: nil)) == nil
    end

    test "Next Episode during a credits chapter at or after 80% with a successor queued" do
      assert Viewing.prompt(viewing(chapter: 2, position_seconds: 2410.0, successor_queued?: true)) ==
               :next_episode
    end

    test "no Next Episode during credits without a successor, or for credits before 80%" do
      assert Viewing.prompt(viewing(chapter: 2, position_seconds: 2410.0)) == nil

      early_credits = [
        %{"title" => "Credits", "time" => 0.0},
        %{"title" => "Story", "time" => 60.0}
      ]

      assert Viewing.prompt(
               viewing(
                 chapters: early_credits,
                 chapter: 0,
                 position_seconds: 5.0,
                 successor_queued?: true
               )
             ) == nil
    end

    test "the countdown in the last 20 s with a successor queued, chapters or not" do
      assert Viewing.prompt(viewing(position_seconds: 2588.0, successor_queued?: true, chapter: 2)) ==
               {:next_episode_in, 12}

      assert Viewing.prompt(
               viewing(chapters: [], chapter: nil, position_seconds: 2599.6, successor_queued?: true)
             ) ==
               {:next_episode_in, 1}
    end

    test "the countdown replaces the credits pill and never shows without a successor" do
      assert Viewing.prompt(viewing(position_seconds: 2590.0, chapter: 2, successor_queued?: true)) ==
               {:next_episode_in, 10}

      assert Viewing.prompt(viewing(position_seconds: 2590.0, chapter: 2)) == nil
    end

    test "nothing without a duration" do
      assert Viewing.prompt(viewing(duration_seconds: 0.0, successor_queued?: true)) == nil
    end
  end

  describe "bitmap subtitle tracks" do
    test "PGS, VobSub and DVB tracks are bitmap; text tracks are not" do
      for codec <- ["hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle", "xsub"] do
        assert Viewing.bitmap_track?(%Track{index: 1, codec: codec}), codec
      end

      for codec <- ["subrip", "ass", "webvtt", "mov_text", nil] do
        refute Viewing.bitmap_track?(%Track{index: 1, codec: codec}), inspect(codec)
      end
    end
  end
end
