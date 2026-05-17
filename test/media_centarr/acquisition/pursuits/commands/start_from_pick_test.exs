defmodule MediaCentarr.Acquisition.Pursuits.Commands.StartFromPickTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Commands.StartFromPick
  alias MediaCentarr.Acquisition.Pursuits.Events.{PursuitStarted, ReleasePicked}
  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Search.SearchResult
  alias MediaCentarr.Topics

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
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.acquisition_updates())

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
      assert pursuit.attempt_count == 1
      refute is_nil(pursuit.current_target_id)
      assert pursuit.tried_release_guids == ["abc-123"]

      target = Repo.get!(Target, pursuit.current_target_id)
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
