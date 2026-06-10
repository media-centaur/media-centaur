defmodule MediaCentaur.Acquisition.Pursuits.IdentityVerifierTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Pursuits.{Event, IdentityVerifier, Pursuit, Units}

  defp job(pursuit, file_path, extra \\ %{}) do
    %Oban.Job{
      args: Map.merge(%{"pursuit_id" => pursuit.id, "file_path" => file_path}, extra)
    }
  end

  defp unit_states(pursuit_id) do
    pursuit_id
    |> Units.for_pursuit()
    |> Map.new(fn unit -> {{unit.season_number, unit.episode_number}, unit.state} end)
  end

  describe "perform/1 — movie pursuits" do
    test "a landed movie satisfies the pursuit and records the landing" do
      {pursuit, _target} =
        create_pursuit_with_target(%{tmdb_id: "100", title: "Sample Movie", year: 2024})

      path = "/watch/movies/Sample.Movie.2024.1080p.WEB-DL.H264.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"

      kinds = Enum.map(Repo.all(Event), & &1.kind)
      assert "identity_verified" in kinds
      assert "pursuit_satisfied" in kinds
    end

    test "provenance over filenames: a landing dispatched by TMDB identity satisfies even when the filename looks foreign" do
      # The listener only dispatches when the pipeline already resolved
      # the file to this pursuit's TMDB id. A weird release name must
      # not overrule that identity (the old TitleMatcher gate cancelled
      # here — the Orville incident class).
      {pursuit, _target} =
        create_pursuit_with_target(%{tmdb_id: "100", title: "Sample Movie", year: 2024})

      path = "/watch/movies/totally-cryptic-release-name.mkv"

      assert :ok = IdentityVerifier.perform(job(pursuit, path))

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
      refute "pursuit_cancelled" in Enum.map(Repo.all(Event), & &1.kind)
    end
  end

  describe "perform/1 — composite TV pursuits (the Orville regression)" do
    # A plan-created S2+S3 pursuit: nil season/episode at the parent,
    # identity on the units. The first landed file (a non-lead unit)
    # must satisfy ITS unit — never cancel the pursuit, never satisfy
    # the lead's units (ADR-055; campaign pursuit-identity-and-lifecycle).
    defp composite_pursuit do
      {pursuit, lead_target} =
        create_pursuit_with_target(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 2,
          episode_number: 1
        })

      {:ok, pursuit} =
        pursuit
        |> Ecto.Changeset.change(season_number: nil, episode_number: nil)
        |> Repo.update()

      [lead_unit] = Units.for_pursuit(pursuit.id)

      {:ok, _lead_unit} =
        lead_unit
        |> Ecto.Changeset.change(season_number: 2, episode_number: 1)
        |> Repo.update()

      e307 = create_pursuit_unit(pursuit, %{season_number: 3, episode_number: 7})
      _e308 = create_pursuit_unit(pursuit, %{season_number: 3, episode_number: 8})

      single_target =
        create_covering_target(pursuit, [e307], %{release_title: "Sample.Show.S03E07.1080p"})

      %{pursuit: pursuit, lead_target: lead_target, single_target: single_target}
    end

    test "a non-lead landing satisfies its own unit and leaves the pursuit active" do
      %{pursuit: pursuit} = composite_pursuit()

      path = "/watch/tv/Sample.Show.S03E07.1080p.WEB.mkv"

      assert :ok =
               IdentityVerifier.perform(
                 job(pursuit, path, %{"season_number" => 3, "episode_number" => 7})
               )

      assert unit_states(pursuit.id) == %{
               {2, 1} => "active",
               {3, 7} => "satisfied",
               {3, 8} => "active"
             }

      assert Repo.get!(Pursuit, pursuit.id).state == "active"

      kinds = Enum.map(Repo.all(Event), & &1.kind)
      refute "pursuit_cancelled" in kinds
      refute "identity_mismatch" in kinds
      assert "identity_verified" in kinds
    end

    test "a landing for an episode the pursuit never wanted is ignored" do
      %{pursuit: pursuit} = composite_pursuit()

      assert :ok =
               IdentityVerifier.perform(
                 job(pursuit, "/watch/tv/Sample.Show.S03E09.mkv", %{
                   "season_number" => 3,
                   "episode_number" => 9
                 })
               )

      assert Repo.get!(Pursuit, pursuit.id).state == "active"
      assert Enum.all?(unit_states(pursuit.id), fn {_unit, state} -> state == "active" end)
      assert Repo.all(Event) == []
    end

    test "a duplicate landing for an already-satisfied unit is a no-op" do
      %{pursuit: pursuit} = composite_pursuit()
      args = %{"season_number" => 3, "episode_number" => 7}

      assert :ok = IdentityVerifier.perform(job(pursuit, "/watch/a.mkv", args))
      events_after_first = length(Repo.all(Event))

      assert :ok = IdentityVerifier.perform(job(pursuit, "/watch/b.mkv", args))

      assert length(Repo.all(Event)) == events_after_first
      assert unit_states(pursuit.id)[{3, 7}] == "satisfied"
    end

    test "the pursuit folds to satisfied once every unit has landed" do
      %{pursuit: pursuit} = composite_pursuit()

      for {season, episode} <- [{2, 1}, {3, 7}, {3, 8}] do
        assert :ok =
                 IdentityVerifier.perform(
                   job(pursuit, "/watch/s#{season}e#{episode}.mkv", %{
                     "season_number" => season,
                     "episode_number" => episode
                   })
                 )
      end

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end

    test "a TV landing without unit identity (legacy job, season-only publish) defers to the reconciler" do
      %{pursuit: pursuit} = composite_pursuit()

      assert :ok = IdentityVerifier.perform(job(pursuit, "/watch/tv/Sample.Show.S03.pack/"))

      assert Repo.get!(Pursuit, pursuit.id).state == "active"
      assert Enum.all?(unit_states(pursuit.id), fn {_unit, state} -> state == "active" end)
      assert Repo.all(Event) == []
    end

    test "satisfying a unit whose target covers siblings satisfies the covered span" do
      # A landed pack member satisfies every unit the pack target covers
      # (the torrent landed whole) — same semantics as LibraryReconciler.
      %{pursuit: pursuit} = composite_pursuit()

      [e307, e308] =
        pursuit.id
        |> Units.for_pursuit()
        |> Enum.filter(&(&1.season_number == 3))

      _pack = create_covering_target(pursuit, [e307, e308], %{release_title: "Sample.Show.S03.pack"})

      assert :ok =
               IdentityVerifier.perform(
                 job(pursuit, "/watch/tv/pack/s03e07.mkv", %{
                   "season_number" => 3,
                   "episode_number" => 7
                 })
               )

      states = unit_states(pursuit.id)
      assert states[{3, 7}] == "satisfied"
      assert states[{3, 8}] == "satisfied"
      assert states[{2, 1}] == "active"
      assert Repo.get!(Pursuit, pursuit.id).state == "active"
    end
  end

  describe "perform/1 — single-unit TV pursuits" do
    test "the wanted episode satisfies the pursuit" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 1,
          episode_number: 3
        })

      assert :ok =
               IdentityVerifier.perform(
                 job(pursuit, "/watch/tv/Sample.Show.S01E03.mkv", %{
                   "season_number" => 1,
                   "episode_number" => 3
                 })
               )

      assert Repo.get!(Pursuit, pursuit.id).state == "satisfied"
    end

    test "a different episode of the same show never cancels (old mismatch contract retired)" do
      {pursuit, _target} =
        create_pursuit_with_target(%{
          tmdb_id: "200",
          tmdb_type: "tv",
          title: "Sample Show",
          year: nil,
          season_number: 1,
          episode_number: 3
        })

      assert :ok =
               IdentityVerifier.perform(
                 job(pursuit, "/watch/tv/Sample.Show.S01E04.mkv", %{
                   "season_number" => 1,
                   "episode_number" => 4
                 })
               )

      reloaded = Repo.get!(Pursuit, pursuit.id)
      assert reloaded.state == "active"
      refute "pursuit_cancelled" in Enum.map(Repo.all(Event), & &1.kind)
    end
  end

  describe "perform/1 — skip rules" do
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

      events = Enum.filter(Repo.all(Event), &(&1.kind in ~w(identity_verified identity_mismatch)))

      assert events == []
    end
  end
end
