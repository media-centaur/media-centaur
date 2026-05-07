defmodule MediaCentarr.Acquisition.Pursuits.Commands.StartTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.Start
  alias MediaCentarr.Acquisition.Pursuits.Events.PursuitStarted
  alias MediaCentarr.Topics

  describe "execute/1" do
    test "creates a pursuit row and records a PursuitStarted event" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())

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

    test "manual origin produces a pursuit with origin=manual" do
      args = %{
        tmdb_id: "guid-abc",
        tmdb_type: "manual",
        title: "Manual Pick",
        origin: "manual"
      }

      assert {:ok, %Pursuit{origin: "manual"}} = Start.execute(args)

      [event_row] = Repo.all(Event)
      assert event_row.payload == %{"origin" => "manual"}
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
