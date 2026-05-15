defmodule MediaCentarr.SubtitlesTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Subtitles
  alias MediaCentarr.Subtitles.Track

  describe "create_track/1" do
    test "persists a track with required attributes" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})

      assert {:ok, %Track{} = track} =
               Subtitles.create_track(%{
                 watched_file_id: watched_file.id,
                 kind: :embedded,
                 language: "en",
                 source: "stream:2"
               })

      assert track.watched_file_id == watched_file.id
      assert track.kind == :embedded
      assert track.language == "en"
      assert track.source == "stream:2"
    end

    test "permits nil language (for unknown-language sidecars)" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})

      assert {:ok, track} =
               Subtitles.create_track(%{
                 watched_file_id: watched_file.id,
                 kind: :sidecar,
                 language: nil,
                 source: "/x/Movie.forced.srt"
               })

      assert track.language == nil
    end

    test "rejects missing required fields" do
      assert {:error, changeset} = Subtitles.create_track(%{})

      assert %{
               watched_file_id: ["can't be blank"],
               kind: ["can't be blank"],
               source: ["can't be blank"]
             } = errors_on(changeset)
    end
  end

  describe "list_tracks_for_file/1" do
    test "returns every track linked to the WatchedFile" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, first} =
        Subtitles.create_track(%{
          watched_file_id: watched_file.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      {:ok, second} =
        Subtitles.create_track(%{
          watched_file_id: watched_file.id,
          kind: :embedded,
          language: "fr",
          source: "stream:3"
        })

      assert Enum.sort_by(Subtitles.list_tracks_for_file(watched_file.id), & &1.source) ==
               Enum.sort_by([first, second], & &1.source)
    end

    test "returns [] when the file has no tracks" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})
      assert Subtitles.list_tracks_for_file(watched_file.id) == []
    end

    test "scopes to the requested file only" do
      file_a = create_linked_file(%{movie_id: create_standalone_movie().id})
      file_b = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, track} =
        Subtitles.create_track(%{
          watched_file_id: file_a.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      assert Subtitles.list_tracks_for_file(file_a.id) == [track]
      assert Subtitles.list_tracks_for_file(file_b.id) == []
    end
  end

  describe "replace_tracks_for_file/2" do
    test "replaces the existing track set atomically" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, _initial} =
        Subtitles.create_track(%{
          watched_file_id: watched_file.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      assert {:ok, [%Track{language: "fr"}, %Track{language: "es"}]} =
               Subtitles.replace_tracks_for_file(watched_file.id, [
                 %{kind: :embedded, language: "fr", source: "stream:3"},
                 %{kind: :sidecar, language: "es", source: "/x/Movie.es.srt"}
               ])

      languages =
        watched_file.id
        |> Subtitles.list_tracks_for_file()
        |> Enum.map(& &1.language)
        |> Enum.sort()

      assert languages == ["es", "fr"]
    end

    test "passing an empty list clears tracks" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: watched_file.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      assert {:ok, []} = Subtitles.replace_tracks_for_file(watched_file.id, [])
      assert Subtitles.list_tracks_for_file(watched_file.id) == []
    end

    test "accepts %Track{} structs and normalises to the FK" do
      watched_file = create_linked_file(%{movie_id: create_standalone_movie().id})

      tracks_from_detector = [
        %Track{kind: :embedded, language: "en", source: "stream:2"},
        %Track{kind: :sidecar, language: nil, source: "/x/forced.srt"}
      ]

      assert {:ok, [%Track{language: "en"}, %Track{language: nil}]} =
               Subtitles.replace_tracks_for_file(watched_file.id, tracks_from_detector)

      sources =
        watched_file.id
        |> Subtitles.list_tracks_for_file()
        |> Enum.map(& &1.source)
        |> Enum.sort()

      assert sources == ["/x/forced.srt", "stream:2"]
    end
  end

  describe "aggregate_languages_for_files/1" do
    test "returns [] for an empty file list" do
      assert Subtitles.aggregate_languages_for_files([]) == []
    end

    test "returns [] when files have no tracks" do
      file_a = create_linked_file(%{movie_id: create_standalone_movie().id})
      file_b = create_linked_file(%{movie_id: create_standalone_movie().id})

      assert Subtitles.aggregate_languages_for_files([file_a.id, file_b.id]) == []
    end

    test "extracts and dedupes ISO codes across files" do
      file_a = create_linked_file(%{movie_id: create_standalone_movie().id})
      file_b = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file_a.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file_a.id,
          kind: :embedded,
          language: "es",
          source: "stream:3"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file_b.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file_b.id,
          kind: :embedded,
          language: "fr",
          source: "stream:4"
        })

      assert Subtitles.aggregate_languages_for_files([file_a.id, file_b.id]) == ["en", "es", "fr"]
    end

    test "sorts known languages alphabetically, with nil last for unknown sidecars" do
      file = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :sidecar,
          language: nil,
          source: "/x/Movie.forced.srt"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :embedded,
          language: "fr",
          source: "stream:5"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :embedded,
          language: "de",
          source: "stream:3"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      assert Subtitles.aggregate_languages_for_files([file.id]) == ["de", "en", "fr", nil]
    end

    test "collapses multiple unknown-language sidecars to a single nil" do
      file = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :sidecar,
          language: nil,
          source: "/x/Movie.forced.srt"
        })

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :sidecar,
          language: nil,
          source: "/x/Movie.sdh.srt"
        })

      assert Subtitles.aggregate_languages_for_files([file.id]) == [nil]
    end

    test "accepts WatchedFile structs and resolves their ids" do
      file = create_linked_file(%{movie_id: create_standalone_movie().id})

      {:ok, _} =
        Subtitles.create_track(%{
          watched_file_id: file.id,
          kind: :embedded,
          language: "en",
          source: "stream:2"
        })

      assert Subtitles.aggregate_languages_for_files([file]) == ["en"]
    end
  end
end
