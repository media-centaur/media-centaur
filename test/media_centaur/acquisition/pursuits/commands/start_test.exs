defmodule MediaCentaur.Acquisition.Pursuits.Commands.StartTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits.{Event, Pursuit, Units}
  alias MediaCentaur.Acquisition.Pursuits.Commands.Start
  alias MediaCentaur.Acquisition.Pursuits.Events.PursuitStarted
  alias MediaCentaur.Topics

  describe "execute/1" do
    test "creates a pursuit row and records a PursuitStarted event" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())

      args = %{
        tmdb_id: "12345",
        tmdb_type: "movie",
        title: "Sample Movie",
        origin: "auto"
      }

      assert {:ok, %Pursuit{} = pursuit} = Start.execute(args)

      assert pursuit.tmdb_id == "12345"
      assert pursuit.title == "Sample Movie"
      assert pursuit.origin == "auto"
      assert pursuit.state == "active"

      [event_row] = Repo.all(Event)
      assert event_row.kind == "pursuit_started"
      assert event_row.pursuit_id == pursuit.id
      assert event_row.payload == %{"origin" => "auto"}

      assert_receive %PursuitStarted{pursuit_id: pid, origin: "auto"}
      assert pid == pursuit.id
    end

    test "supports TV episode pursuits with season + episode + criteria" do
      args = %{
        tmdb_id: "999",
        tmdb_type: "tv",
        title: "Sample Show",
        origin: "auto",
        season_number: 1,
        episode_number: 3,
        criteria: %{"min_quality" => "1080p", "max_quality" => "2160p"}
      }

      assert {:ok, %Pursuit{} = pursuit} = Start.execute(args)

      assert pursuit.season_number == 1
      assert pursuit.episode_number == 3
      assert pursuit.criteria == %{"min_quality" => "1080p", "max_quality" => "2160p"}
    end

    test "manual origin (prowlarr_query recipe) produces a pursuit with origin=manual" do
      args = %{
        recipe_type: "prowlarr_query",
        manual_query: "Manual Pick query",
        title: "Manual Pick",
        origin: "manual"
      }

      assert {:ok, %Pursuit{origin: "manual"}} = Start.execute(args)

      [event_row] = Repo.all(Event)
      assert event_row.payload == %{"origin" => "manual"}
    end

    test "orders units by season/episode regardless of the order specs arrive in" do
      args = %{
        tmdb_id: "777",
        tmdb_type: "tv",
        title: "Sample Show",
        origin: "auto",
        units: [
          %{label: "S02E01", season_number: 2, episode_number: 1},
          %{label: "S01E10", season_number: 1, episode_number: 10},
          %{label: "S01E02", season_number: 1, episode_number: 2}
        ]
      }

      assert {:ok, %Pursuit{} = pursuit} = Start.execute(args)

      units = Units.for_pursuit(pursuit.id)

      assert Enum.map(units, & &1.label) == ["S01E02", "S01E10", "S02E01"]
      assert Enum.map(units, & &1.position) == [0, 1, 2]
    end

    test "rolls back the pursuit + event when the pursuit changeset is invalid" do
      args = %{
        # missing tmdb_id, tmdb_type, title — invalid
        origin: "auto"
      }

      assert {:error, %Ecto.Changeset{}} = Start.execute(args)

      assert Repo.aggregate(Pursuit, :count) == 0
      assert Repo.aggregate(Event, :count) == 0
    end
  end
end
