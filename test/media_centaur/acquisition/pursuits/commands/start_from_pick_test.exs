defmodule MediaCentaur.Acquisition.Pursuits.Commands.StartFromPickTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Pursuits.{Event, Pursuit, Units}
  alias MediaCentaur.Acquisition.Pursuits.Commands.StartFromPick
  alias MediaCentaur.Acquisition.Pursuits.Events.{PursuitStarted, ReleasePicked}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Search.SearchResult
  alias MediaCentaur.Topics

  defp result(overrides \\ %{}) do
    defaults = %{
      title: "Sample.Show.S01E01.1080p.WEB-DL.x264",
      guid: "abc-123",
      indexer_id: 7,
      quality: :hd_1080p,
      indexer_name: "Indexer A"
    }

    struct(SearchResult, Map.merge(defaults, overrides))
  end

  describe "execute/1" do
    test "atomically creates a prowlarr_query pursuit + acquired target in one transaction" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.acquisition_updates())

      assert {:ok, %Pursuit{} = pursuit} =
               StartFromPick.execute(%{
                 result: result(),
                 manual_query: "Sample Show S01E01",
                 origin: "manual"
               })

      assert pursuit.recipe_type == "prowlarr_query"
      assert pursuit.manual_query == "Sample Show S01E01"
      assert pursuit.origin == "manual"
      assert pursuit.state == "active"
      unit = MediaCentaur.Acquisition.Pursuits.Units.single!(pursuit.id)
      assert unit.attempt_count == 1
      refute is_nil(unit.current_target_id)
      assert unit.tried_release_guids == ["abc-123"]

      target = Repo.get!(Target, unit.current_target_id)
      assert target.status == "acquired"
      assert target.prowlarr_guid == "abc-123"
      assert target.release_title == "Sample.Show.S01E01.1080p.WEB-DL.x264"
      assert target.origin == "manual"

      assert_receive %PursuitStarted{pursuit_id: pid, origin: "manual"}
      assert pid == pursuit.id

      assert_receive %ReleasePicked{
        pursuit_id: ^pid,
        release_title: "Sample.Show.S01E01.1080p.WEB-DL.x264"
      }
    end

    test "records exactly two events — pursuit_started and release_picked (no decision/fallback)" do
      assert {:ok, pursuit} =
               StartFromPick.execute(%{
                 result: result(),
                 manual_query: "Sample Show S01E01",
                 origin: "manual"
               })

      kinds =
        Event
        |> Repo.all()
        |> Enum.filter(&(&1.pursuit_id == pursuit.id))
        |> Enum.map(& &1.kind)
        |> Enum.sort()

      assert kinds == ["pursuit_started", "release_picked"]
      refute "user_decision_recorded" in kinds
      refute "fallback_initiated" in kinds
    end

    test "orders a multi-pick batch's units by season/episode parsed from the term" do
      picks = [
        %{
          term: "Sample Show S02E01",
          result: result(%{title: "Sample.Show.S02E01.1080p", guid: "g-s2e1"})
        },
        %{
          term: "Sample Show S01E10",
          result: result(%{title: "Sample.Show.S01E10.1080p", guid: "g-s1e10"})
        },
        %{
          term: "Sample Show S01E02",
          result: result(%{title: "Sample.Show.S01E02.1080p", guid: "g-s1e2"})
        }
      ]

      assert {:ok, %{pursuit: pursuit}} =
               StartFromPick.execute(%{
                 picks: picks,
                 manual_query: "Sample Show S0{1-2}E{01-10}",
                 origin: "manual"
               })

      units = Units.for_pursuit(pursuit.id)

      assert Enum.map(units, & &1.label) == [
               "Sample Show S01E02",
               "Sample Show S01E10",
               "Sample Show S02E01"
             ]

      assert Enum.map(units, & &1.position) == [0, 1, 2]
    end

    test "rolls back everything when the pursuit changeset is invalid" do
      assert {:error, %Ecto.Changeset{}} =
               StartFromPick.execute(%{
                 # No manual_query, no result.title backing — invalid recipe
                 result: result(%{title: ""}),
                 manual_query: nil,
                 origin: "manual"
               })

      assert Repo.aggregate(Pursuit, :count) == 0
      assert Repo.aggregate(Target, :count) == 0
      assert Repo.aggregate(Event, :count) == 0
    end
  end
end
