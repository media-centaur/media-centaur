defmodule MediaCentaur.Playback.RememberedTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library
  alias MediaCentaur.Playback.{Entry, Events, Remembered}

  defp movie_entry(movie), do: %Entry{entity_id: movie.id, movie_id: movie.id, content_url: "/a.mkv"}

  describe "load/2 — the title a viewing's settings belong to" do
    test "a movie owns its settings, with its original language" do
      movie = create_movie(%{name: "Sample Movie", original_language: "jpn"})
      remembered = Remembered.load(owner_profile_id(), movie_entry(movie))

      assert remembered.owner_type == :movie
      assert remembered.owner_id == movie.id
      assert remembered.original_language == "jpn"
      assert remembered.override == nil
      assert Remembered.remembers?(remembered)
    end

    test "an episode's settings belong to its whole series" do
      tv_series = create_tv_series(%{original_language: "kor"})

      remembered =
        Remembered.load(owner_profile_id(), %Entry{
          entity_id: tv_series.id,
          episode_id: "fake-episode-uuid",
          content_url: "/a.mkv"
        })

      assert remembered.owner_type == :tv_series
      assert remembered.owner_id == tv_series.id
      assert remembered.original_language == "kor"
    end

    test "normalizes original_language from TMDB's 2-letter form" do
      movie = create_movie(%{name: "Sample Movie", original_language: "ja"})
      assert Remembered.load(owner_profile_id(), movie_entry(movie)).original_language == "jpn"
    end

    test "an extra remembers nothing" do
      remembered =
        Remembered.load(owner_profile_id(), %Entry{
          entity_id: "any",
          extra_id: "some-extra",
          content_url: "/a.mkv"
        })

      refute Remembered.remembers?(remembered)
      assert remembered.override == nil
    end

    test "loads the profile's own override, never another profile's" do
      movie = create_movie(%{name: "Sample Movie"})

      {:ok, _} =
        Library.PlaybackOverrides.upsert(owner_profile_id(), :movie, movie.id, %{fill_width: true})

      assert Remembered.fill_width?(Remembered.load(owner_profile_id(), movie_entry(movie)))

      ana = create_profile(%{name: "Ana"}).id
      refute Remembered.fill_width?(Remembered.load(ana, movie_entry(movie)))
    end
  end

  describe "picture_change/2 — the picture part of a save" do
    setup do
      movie = create_movie(%{name: "Sample Movie"})
      %{remembered: Remembered.load(owner_profile_id(), movie_entry(movie))}
    end

    test "Fit is the default: only Fill width diverges", %{remembered: remembered} do
      assert Remembered.picture_change(remembered, false) == %{}
      assert Remembered.picture_change(remembered, true) == %{fill_width: true}
    end

    test "back to Fit from a remembered Fill width is saved", %{remembered: remembered} do
      remembered = %{remembered | override: %Library.PlaybackOverride{fill_width: true}}
      assert Remembered.picture_change(remembered, false) == %{fill_width: false}
      assert Remembered.picture_change(remembered, true) == %{}
    end

    test "nothing while the player has not reported its picture", %{remembered: remembered} do
      assert Remembered.picture_change(remembered, nil) == %{}
    end
  end

  describe "save/3" do
    test "saves only the fields given, keeps the rest, and broadcasts" do
      movie = create_movie(%{name: "Sample Movie"})
      profile_id = owner_profile_id()
      {:ok, _} = Library.PlaybackOverrides.upsert(profile_id, :movie, movie.id, %{audio_lang: "eng"})
      MediaCentaur.Playback.subscribe()

      remembered =
        profile_id
        |> Remembered.load(movie_entry(movie))
        |> Remembered.save(profile_id, %{fill_width: true})

      assert Remembered.fill_width?(remembered)
      saved = Library.PlaybackOverrides.get(profile_id, :movie, movie.id)
      assert saved.fill_width
      assert saved.audio_lang == "eng"

      movie_id = movie.id
      assert_receive {:playback_override_changed, %Events.PlaybackOverrideChanged{owner_id: ^movie_id}}
    end

    test "nothing to save writes nothing" do
      movie = create_movie(%{name: "Sample Movie"})
      remembered = Remembered.load(owner_profile_id(), movie_entry(movie))

      assert Remembered.save(remembered, owner_profile_id(), %{}) == remembered
      assert Library.PlaybackOverrides.get(owner_profile_id(), :movie, movie.id) == nil
    end
  end
end
