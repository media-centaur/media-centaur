defmodule MediaCentarr.Acquisition.Pursuits.PersistenceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}

  defp create_pursuit(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tmdb_id: "12345",
          tmdb_type: "movie",
          title: "Sample Movie",
          origin: "auto"
        },
        overrides
      )

    {:ok, pursuit} = Repo.insert(Pursuit.create_changeset(attrs))
    pursuit
  end

  describe "Pursuit insertion" do
    test "round-trips with all defaults applied" do
      pursuit = create_pursuit()

      assert pursuit.state == "active"
      assert pursuit.attempt_count == 0
      assert pursuit.tried_release_guids == []
      assert pursuit.criteria == %{}
      assert is_binary(pursuit.id)
    end

    test "criteria map round-trips via JSONB" do
      pursuit =
        create_pursuit(%{
          criteria: %{"min_quality" => "1080p", "max_quality" => "2160p"}
        })

      reloaded = Repo.get!(Pursuit, pursuit.id)
      assert reloaded.criteria == %{"min_quality" => "1080p", "max_quality" => "2160p"}
    end
  end

  describe "Event FK nilify_all" do
    test "pursuit_id is nilified when the pursuit is deleted" do
      pursuit = create_pursuit()

      {:ok, event} =
        Repo.insert(
          Event.create_changeset(%{
            pursuit_id: pursuit.id,
            denormalized_pursuit_title: pursuit.title,
            kind: "pursuit_started",
            payload: %{"origin" => "auto"},
            occurred_at: DateTime.utc_now(:second)
          })
        )

      Repo.delete!(pursuit)
      reloaded = Repo.get!(Event, event.id)

      assert reloaded.pursuit_id == nil
      assert reloaded.denormalized_pursuit_title == "Sample Movie"
    end
  end

  describe "Grab.pursuit_id linkage" do
    test "an existing acquisition_grabs row can carry pursuit_id and excluded_release_guids" do
      pursuit = create_pursuit()

      {:ok, grab} =
        %MediaCentarr.Acquisition.Grab{}
        |> Ecto.Changeset.cast(
          %{
            tmdb_id: pursuit.tmdb_id,
            tmdb_type: pursuit.tmdb_type,
            title: pursuit.title,
            origin: pursuit.origin
          },
          [:tmdb_id, :tmdb_type, :title, :origin]
        )
        |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
        |> Ecto.Changeset.put_change(:excluded_release_guids, ["guid-a", "guid-b"])
        |> Repo.insert()

      reloaded = Repo.get!(MediaCentarr.Acquisition.Grab, grab.id)
      assert reloaded.pursuit_id == pursuit.id
      assert reloaded.excluded_release_guids == ["guid-a", "guid-b"]
    end

    test "grab.pursuit_id is nilified when the pursuit is deleted" do
      pursuit = create_pursuit()

      {:ok, grab} =
        %MediaCentarr.Acquisition.Grab{}
        |> Ecto.Changeset.cast(
          %{
            tmdb_id: pursuit.tmdb_id,
            tmdb_type: pursuit.tmdb_type,
            title: pursuit.title,
            origin: pursuit.origin
          },
          [:tmdb_id, :tmdb_type, :title, :origin]
        )
        |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
        |> Repo.insert()

      Repo.delete!(pursuit)
      reloaded = Repo.get!(MediaCentarr.Acquisition.Grab, grab.id)
      assert reloaded.pursuit_id == nil
    end
  end
end
