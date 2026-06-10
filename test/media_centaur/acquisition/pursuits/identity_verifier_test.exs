defmodule MediaCentaur.Acquisition.Pursuits.IdentityVerifierTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, IdentityVerifier, Pursuit}

  defp job(pursuit, file_path) do
    %Oban.Job{args: %{"pursuit_id" => pursuit.id, "file_path" => file_path}}
  end

  describe "perform/1" do
    test "filename matches pursuit → records IdentityVerified, transitions to satisfied" do
      {pursuit, _target} =
        create_pursuit_with_target(%{tmdb_id: "100", title: "Sample Movie", year: 2024})

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
    end

    test "TV episode match honours season + episode" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 1,
          episode_number: 3
        })

      path = "/watch/tv/Sample.Show.S01E03.1080p.WEB-DL.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end

    test "wrong show in filename → records IdentityMismatch, cancels pursuit" do
      {pursuit, _target} =
        create_pursuit_with_target(%{tmdb_id: "100", title: "Sample Movie", year: 2024})

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

    test "mismatch description reads the unit's identity, not the parent's (ADR-055)" do
      # Plan-created tmdb pursuits carry season/episode only on units —
      # the parent columns are the auto-path idempotency key and may be
      # nil. The "expected X" description must still name the episode.
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "300",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 2,
          episode_number: 7
        })

      {:ok, pursuit} =
        pursuit
        |> Ecto.Changeset.change(season_number: nil, episode_number: nil)
        |> Repo.update()

      unit = MediaCentaur.Acquisition.Pursuits.Units.single!(pursuit.id)

      {:ok, _unit} =
        unit
        |> Ecto.Changeset.change(season_number: 2, episode_number: 7)
        |> Repo.update()

      path = "/watch/tv/Other.Show.S05E05.1080p.WEB-DL.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      events = Repo.all(Event)
      mismatch = Enum.find(events, &(&1.kind == "identity_mismatch"))
      assert mismatch.payload["expected"] == "Sample Show S02E07"
    end

    test "wrong episode number → mismatch (S01E04 should not satisfy a S01E03 pursuit)" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 1,
          episode_number: 3
        })

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
      {pursuit, _target} = create_pursuit_with_target()

      pursuit
      |> Ecto.Changeset.change(state: "satisfied")
      |> Repo.update!()

      assert :ok = IdentityVerifier.perform(job(pursuit, "/anything.mkv"))

      # Only the change of state above happened; no IdentityVerifier events.
      events = Enum.filter(Repo.all(Event), &(&1.kind in ~w(identity_verified identity_mismatch)))

      assert events == []
    end
  end
end
