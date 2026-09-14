defmodule MediaCentaurWeb.Live.TitleDetailHost.LibraryHalfTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Detail, as: TitleDetail
  alias MediaCentaurWeb.Components.Title.Detail.Library
  alias MediaCentaurWeb.Live.TitleDetailHost.LibraryHalf
  alias MediaCentaurWeb.ViewModel.LeafDetail
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  describe "reload/1" do
    test "a TV series keeps its typed seasons (regression: episode list vanished on player close)" do
      tv = create_tv_series_with_one_episode("Sample Show")
      half = LibraryHalf.load_entity(tv.id)

      reloaded = LibraryHalf.reload(half)

      assert %SeriesDetail{seasons: seasons} = reloaded.entry
      assert length(seasons) == 1
    end

    test "a movie still reloads into a renderable entry, keeping its files" do
      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})
      half = %{LibraryHalf.load_entity(movie.id) | files: {:ok, [%{file: :one}]}}

      reloaded = LibraryHalf.reload(half)

      assert %LeafDetail{} = reloaded.entry
      assert reloaded.entry.entity.id == movie.id
      assert reloaded.files == {:ok, [%{file: :one}]}
    end

    test "an entity that lost its files reloads to nothing" do
      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})
      half = LibraryHalf.load_entity(movie.id)

      assert LibraryHalf.reload(%{
               half
               | entry: %{half.entry | entity: %{half.entry.entity | id: Ecto.UUID.generate()}}
             }) ==
               nil
    end
  end

  describe "address/1 — what an entity emitter's id resolves to" do
    test "a titled movie: its title address" do
      movie = create_standalone_movie(%{name: "Sample Movie", tmdb_id: "777"})
      create_linked_file(%{movie_id: movie.id})
      assert {:title, {777, :movie}, %Library{}} = LibraryHalf.address(movie.id)
    end

    test "an unmatched movie: the entity address (the residue)" do
      movie = create_standalone_movie(%{name: "Unmatched Movie"})
      create_linked_file(%{movie_id: movie.id})
      assert {:entity, id, %Library{}} = LibraryHalf.address(movie.id)
      assert id == movie.id
    end

    test "an id the library has no present file for: not found" do
      assert LibraryHalf.address(Ecto.UUID.generate()) == :not_found
    end
  end

  describe "apply_files/3 — the deferred file-info load lands by subject" do
    defp open_socket(detail) do
      %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, title_detail: detail}}
    end

    defp owned_detail(ref) do
      entity = %{id: "a", type: :movie, name: "Sample Movie"}

      %TitleDetail{
        ref: ref,
        title: ref && Title.new!(%{tmdb_id: elem(ref, 0), media_type: :movie, name: "Sample Movie"}),
        library: %Library{
          entry: %LeafDetail{entity: entity, progress: nil, progress_records: [], resume_target: nil},
          subject: entity,
          files: :loading
        }
      }
    end

    test "a result for the open subject lands the files as loaded" do
      socket = open_socket(owned_detail({777, :movie}))
      socket = LibraryHalf.apply_files(socket, {:title, {777, :movie}}, {:ok, [%{file: :one}]})
      assert socket.assigns.title_detail.library.files == {:ok, [%{file: :one}]}
    end

    test "a crashed load for the open subject marks the files failed, never 'no files'" do
      socket = open_socket(owned_detail({777, :movie}))
      socket = LibraryHalf.apply_files(socket, {:title, {777, :movie}}, {:exit, :boom})
      assert socket.assigns.title_detail.library.files == :failed
    end

    test "a result or crash for a subject the person moved on from is dropped" do
      socket = open_socket(owned_detail({778, :movie}))

      assert LibraryHalf.apply_files(socket, {:title, {777, :movie}}, {:ok, [%{}]}).assigns.title_detail.library.files ==
               :loading

      assert LibraryHalf.apply_files(socket, {:title, {777, :movie}}, {:exit, :boom}).assigns.title_detail.library.files ==
               :loading
    end

    test "the residue lands by its entity id" do
      socket = open_socket(owned_detail(nil))
      socket = LibraryHalf.apply_files(socket, {:entity, "a"}, {:ok, []})
      assert socket.assigns.title_detail.library.files == {:ok, []}
    end
  end

  defp create_tv_series_with_one_episode(name) do
    tv = create_tv_series(%{name: name})
    season = create_season(%{tv_series_id: tv.id, season_number: 1, number_of_episodes: 1})

    episode =
      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/tv/#{name}/s01e01.mkv"
      })

    playable_item = create_playable_item_for_episode(episode)
    create_linked_file(%{playable_item_id: playable_item.id, file_path: episode.content_url})
    tv
  end
end
