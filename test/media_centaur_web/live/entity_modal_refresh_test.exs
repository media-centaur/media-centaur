defmodule MediaCentaurWeb.Live.EntityModalRefreshTest do
  # `refresh_selected_entry/1` reloads the open modal entry after an
  # entity-level mutation (player close, releases update, item removed,
  # entities_changed). It must produce the *same typed shape* the fresh
  # open produces — for a TV series that means a `%SeriesDetail{}` with a
  # populated `seasons` list, not a plain map whose seasons the renderer
  # silently drops.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaurWeb.Live.EntityModal
  alias MediaCentaurWeb.ViewModel.SeriesDetail

  describe "refresh_selected_entry/1" do
    test "a TV series keeps its typed seasons (regression: episode list vanished on player close)" do
      tv = create_tv_series_with_one_episode("Sample Show")

      refreshed = EntityModal.refresh_selected_entry(socket_for(tv.id))

      assert %SeriesDetail{} = refreshed.assigns.selected_entry

      seasons = EntityModal.seasons_view_from_entry(refreshed.assigns.selected_entry)
      assert is_list(seasons)
      assert length(seasons) == 1
    end

    test "a movie still refreshes into a renderable entry" do
      movie = create_movie(%{name: "Sample Movie"})
      create_linked_file(%{movie_id: movie.id})

      refreshed = EntityModal.refresh_selected_entry(socket_for(movie.id))

      entry = refreshed.assigns.selected_entry
      assert entry != nil
      assert entry.entity.id == movie.id
      # Non-TV entries carry no typed seasons; the renderer falls back.
      assert EntityModal.seasons_view_from_entry(entry) == nil
    end
  end

  defp socket_for(entity_id) do
    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:selected_entity_id, entity_id)
    |> Phoenix.Component.assign(:selected_entry, nil)
    |> Phoenix.Component.assign(:detail_presentation, :modal)
  end

  defp create_tv_series_with_one_episode(name) do
    tv = create_tv_series(%{name: name})
    season = create_season(%{tv_series_id: tv.id, season_number: 1, number_of_episodes: 1})

    episode =
      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/test/#{tv.id}-s01e01.mkv"
      })

    playable_item = create_playable_item_for_episode(episode)
    create_linked_file(%{playable_item_id: playable_item.id, file_path: episode.content_url})

    tv
  end
end
