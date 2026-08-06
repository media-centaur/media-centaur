defmodule MediaCentaur.Playback.PlayableFksTest do
  @moduledoc """
  Pure per-type dispatch shared by `Resolver` and `SessionRecovery`. The
  module exists so the entity-type → FK mapping cannot drift between those
  two callers, which makes an unrecognised type falling through to the
  catch-all the failure worth pinning.
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.Playback.PlayableFks

  defp tv_series(episodes) do
    %{
      type: :tv_series,
      id: "series-1",
      seasons: [
        %{
          season_number: 1,
          episodes: episodes
        }
      ]
    }
  end

  defp episode(id, number, content_url, name) do
    %{id: id, episode_number: number, content_url: content_url, name: name}
  end

  defp movie_series(movies) do
    %{type: :movie_series, id: "series-1", movies: movies}
  end

  # `MovieList.sort_movies/1` orders by release date then position, so the
  # fixture has to carry `:date_published` — a movie row without it is not
  # a shape the projection ever produces.
  defp movie(id, name, content_url, position, date_published) do
    %{
      id: id,
      name: name,
      content_url: content_url,
      position: position,
      date_published: date_published
    }
  end

  describe "resolve/2" do
    test "a movie resolves to its own id, ignoring the content_url" do
      entity = %{type: :movie, id: "movie-1"}

      assert PlayableFks.resolve(entity, "/media/anything.mkv") == %{movie_id: "movie-1"}
      assert PlayableFks.resolve(entity, nil) == %{movie_id: "movie-1"}
    end

    test "a video object resolves to its own id" do
      entity = %{type: :video_object, id: "video-1"}

      assert PlayableFks.resolve(entity, "/media/clip.mkv") == %{video_object_id: "video-1"}
    end

    test "a tv series resolves to the episode matching the content_url" do
      entity =
        tv_series([
          episode("ep-1", 1, "/media/s01e01.mkv", "Pilot"),
          episode("ep-2", 2, "/media/s01e02.mkv", "Second")
        ])

      assert PlayableFks.resolve(entity, "/media/s01e02.mkv") == %{episode_id: "ep-2"}
    end

    test "a tv series with no matching content_url resolves to a nil episode_id" do
      entity = tv_series([episode("ep-1", 1, "/media/s01e01.mkv", "Pilot")])

      assert PlayableFks.resolve(entity, "/media/absent.mkv") == %{episode_id: nil}
    end

    test "a tv series with no seasons or episodes does not raise" do
      assert PlayableFks.resolve(%{type: :tv_series, id: "s", seasons: nil}, "/x") ==
               %{episode_id: nil}

      assert PlayableFks.resolve(
               %{type: :tv_series, id: "s", seasons: [%{season_number: 1, episodes: nil}]},
               "/x"
             ) == %{episode_id: nil}
    end

    test "a movie series resolves to the movie matching the content_url" do
      entity =
        movie_series([
          movie("movie-1", "First", "/media/first.mkv", 1, ~D[2001-01-01]),
          movie("movie-2", "Second", "/media/second.mkv", 2, ~D[2002-01-01])
        ])

      assert PlayableFks.resolve(entity, "/media/second.mkv") == %{movie_id: "movie-2"}
    end

    test "a movie series with no matching content_url resolves to a nil movie_id" do
      entity = movie_series([movie("movie-1", "First", "/media/first.mkv", 1, ~D[2001-01-01])])

      assert PlayableFks.resolve(entity, "/media/absent.mkv") == %{movie_id: nil}
    end

    test "an unrecognised entity type resolves to an empty FK map" do
      assert PlayableFks.resolve(%{type: :something_new, id: "x"}, "/media/a.mkv") == %{}
      assert PlayableFks.resolve(%{}, nil) == %{}
    end
  end

  describe "context_by_url/2" do
    test "a tv series yields {season, episode, name}" do
      entity =
        tv_series([
          episode("ep-1", 1, "/media/s01e01.mkv", "Pilot"),
          episode("ep-2", 2, "/media/s01e02.mkv", "Second")
        ])

      assert PlayableFks.context_by_url(entity, "/media/s01e02.mkv") == {1, 2, "Second"}
    end

    test "a tv series with no match yields an all-nil context" do
      entity = tv_series([episode("ep-1", 1, "/media/s01e01.mkv", "Pilot")])

      assert PlayableFks.context_by_url(entity, "/media/absent.mkv") == {nil, nil, nil}
    end

    test "a movie series yields {0, ordinal, name} — season zero marks a flat list" do
      entity =
        movie_series([
          movie("movie-1", "First", "/media/first.mkv", 1, ~D[2001-01-01]),
          movie("movie-2", "Second", "/media/second.mkv", 2, ~D[2002-01-01])
        ])

      assert {0, ordinal, "Second"} = PlayableFks.context_by_url(entity, "/media/second.mkv")
      assert is_integer(ordinal)
    end

    test "a movie series with no matching content_url yields an all-nil context" do
      entity = movie_series([movie("movie-1", "First", "/media/first.mkv", 1, ~D[2001-01-01])])

      assert PlayableFks.context_by_url(entity, "/media/absent.mkv") == {nil, nil, nil}
    end

    test "an unrecognised entity type yields an all-nil context" do
      assert PlayableFks.context_by_url(%{type: :movie, id: "m"}, "/media/a.mkv") ==
               {nil, nil, nil}

      assert PlayableFks.context_by_url(%{}, nil) == {nil, nil, nil}
    end
  end
end
