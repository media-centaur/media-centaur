defmodule MediaCentarr.Acquisition.Pursuits.IdentityVerifierTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Event, IdentityVerifier, Pursuit}

  defp insert_pursuit(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          tmdb_id: "100",
          tmdb_type: "movie",
          title: "Sample Movie",
          year: 2024,
          origin: "auto"
        },
        overrides
      )

    {:ok, pursuit} = Repo.insert(Pursuit.create_changeset(attrs))
    pursuit
  end

  defp insert_grab(pursuit) do
    %Grab{}
    |> Ecto.Changeset.cast(
      %{
        tmdb_id: pursuit.tmdb_id,
        tmdb_type: pursuit.tmdb_type,
        title: pursuit.title,
        year: pursuit.year,
        season_number: pursuit.season_number,
        episode_number: pursuit.episode_number,
        origin: pursuit.origin
      },
      [:tmdb_id, :tmdb_type, :title, :year, :season_number, :episode_number, :origin]
    )
    |> Ecto.Changeset.put_change(:pursuit_id, pursuit.id)
    |> Repo.insert!()
  end

  defp job(pursuit, file_path) do
    %Oban.Job{args: %{"pursuit_id" => pursuit.id, "file_path" => file_path}}
  end

  describe "perform/1" do
    test "filename matches pursuit → records IdentityVerified, transitions to satisfied" do
      pursuit = insert_pursuit(%{title: "Sample Movie", year: 2024})
      grab = insert_grab(pursuit)
      path = "/watch/movies/Sample.Movie.2024.1080p.WEB-DL.H264.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      reloaded = Repo.get!(Pursuit, pursuit.id)
      assert reloaded.state == "satisfied"

      events = Repo.all(Event)
      kinds = Enum.map(events, & &1.kind)
      assert "identity_verified" in kinds
      assert "pursuit_satisfied" in kinds

      verified = Enum.find(events, &(&1.kind == "identity_verified"))
      assert verified.payload["file_path"] == path

      _ = grab
    end

    test "TV episode match honours season + episode" do
      pursuit =
        insert_pursuit(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 1,
          episode_number: 3
        })

      _grab = insert_grab(pursuit)
      path = "/watch/tv/Sample.Show.S01E03.1080p.WEB-DL.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end

    test "wrong show in filename → records IdentityMismatch, cancels pursuit" do
      pursuit = insert_pursuit(%{title: "Sample Movie", year: 2024})
      _grab = insert_grab(pursuit)
      path = "/watch/movies/Different.Movie.2010.1080p.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      reloaded = Repo.get!(Pursuit, pursuit.id)
      assert reloaded.state == "cancelled"

      events = Repo.all(Event)
      kinds = Enum.map(events, & &1.kind)
      assert "identity_mismatch" in kinds
      assert "pursuit_cancelled" in kinds

      mismatch = Enum.find(events, &(&1.kind == "identity_mismatch"))
      assert mismatch.payload["file_path"] == path
      assert mismatch.payload["expected"] =~ "Sample Movie"
      assert mismatch.payload["observed"] =~ "Different"
    end

    test "wrong episode number → mismatch (S01E04 should not satisfy a S01E03 pursuit)" do
      pursuit =
        insert_pursuit(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 1,
          episode_number: 3
        })

      _grab = insert_grab(pursuit)
      path = "/watch/tv/Sample.Show.S01E04.1080p.WEB-DL.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      assert Repo.get!(Pursuit, pursuit.id).state == "cancelled"
    end

    test "skips silently when the pursuit no longer exists" do
      ghost_id = Ecto.UUID.generate()

      assert :ok =
               IdentityVerifier.perform(%Oban.Job{
                 args: %{"pursuit_id" => ghost_id, "file_path" => "/x.mkv"}
               })
    end

    test "skips silently when the pursuit is already terminal" do
      pursuit = insert_pursuit() |> Ecto.Changeset.change(state: "satisfied") |> Repo.update!()
      _grab = insert_grab(pursuit)

      assert :ok = IdentityVerifier.perform(job(pursuit, "/anything.mkv"))

      events = Repo.all(Event)
      assert Enum.empty?(events)
    end

    test "skips silently when the pursuit has no grab" do
      pursuit = insert_pursuit()

      assert :ok = IdentityVerifier.perform(job(pursuit, "/anything.mkv"))

      assert Repo.get!(Pursuit, pursuit.id).state == "active"
      assert Repo.all(Event) == []
    end
  end
end
