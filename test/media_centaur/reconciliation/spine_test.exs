defmodule MediaCentaur.Reconciliation.SpineTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Reconciliation.{Spine, SpineNode}

  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client(self())
    :ok
  end

  # NOTE: stub_routes matches by substring, so the season path must precede
  # the bare /tv/:id path (the latter is a prefix of the former).
  defp stub_show(tmdb_id, seasons, episodes_by_season) do
    season_routes =
      Enum.map(episodes_by_season, fn {season_number, episodes} ->
        {"/tv/#{tmdb_id}/season/#{season_number}",
         TmdbStubs.season_detail(%{"season_number" => season_number, "episodes" => episodes})}
      end)

    tv_route =
      {"/tv/#{tmdb_id}",
       TmdbStubs.tv_detail(%{
         "id" => tmdb_id,
         "seasons" => Enum.map(seasons, &%{"season_number" => &1})
       })}

    TmdbStubs.stub_routes(season_routes ++ [tv_route])
  end

  describe "assemble/2" do
    test "builds spine nodes from TMDB's canonical episodes, marking the present-set" do
      stub_show(42, [1], %{
        1 => [
          %{"episode_number" => 1, "name" => "Alpha"},
          %{"episode_number" => 2, "name" => "Beta"},
          %{"episode_number" => 3, "name" => "Gamma"}
        ]
      })

      spine = Spine.assemble(42, MapSet.new([{1, 1}]))

      assert length(spine) == 3
      assert %SpineNode{season: 1, episode: 1, title: "Alpha", present?: true} = at(spine, 1, 1)
      assert %SpineNode{episode: 2, title: "Beta", present?: false} = at(spine, 1, 2)
      assert %SpineNode{episode: 3, present?: false} = at(spine, 1, 3)
    end

    test "spans multiple seasons including season 0 specials" do
      stub_show(7, [0, 1], %{
        0 => [%{"episode_number" => 1, "name" => "OVA"}],
        1 => [%{"episode_number" => 1, "name" => "Alpha"}]
      })

      spine = Spine.assemble(7, MapSet.new())

      assert at(spine, 0, 1).title == "OVA"
      assert at(spine, 1, 1).title == "Alpha"
    end

    test "degrades to an empty spine when the show fetch fails" do
      TmdbStubs.stub_tmdb_error("/tv/999", 500)

      assert Spine.assemble(999, MapSet.new()) == []
    end

    test "skips a season whose fetch fails rather than crashing" do
      # Only the bare /tv route is stubbed; the season fetch 404s.
      TmdbStubs.stub_routes([
        {"/tv/13", TmdbStubs.tv_detail(%{"id" => 13, "seasons" => [%{"season_number" => 1}]})}
      ])

      assert Spine.assemble(13, MapSet.new()) == []
    end
  end

  defp at(spine, season, episode) do
    Enum.find(spine, &(&1.season == season and &1.episode == episode))
  end
end
