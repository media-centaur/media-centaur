defmodule MediaCentarr.MaintenanceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library.{
    ExternalIds,
    Movie,
    MovieSeries,
    Person,
    PlayableItem,
    TVSeries
  }

  alias MediaCentarr.Maintenance
  alias MediaCentarr.Repo
  alias MediaCentarr.Review

  import MediaCentarr.TestFactory
  import MediaCentarr.TmdbStubs

  # TMDB/IMDB ids live on `library_external_ids` rows now
  # (Library Schema v2 Phase 1 Task 6). Helpers to seed a container
  # with a TMDB ExternalId attached, mirroring how Inbound writes
  # them today.
  defp seed_movie_with_tmdb!(attrs, tmdb_id) when is_map(attrs) do
    {:ok, movie} = attrs |> Movie.create_changeset() |> Repo.insert()
    {:ok, _} = ExternalIds.put(:tmdb, movie, tmdb_id)
    movie
  end

  defp seed_tv_series_with_tmdb!(attrs, tmdb_id) when is_map(attrs) do
    {:ok, series} = attrs |> TVSeries.create_changeset() |> Repo.insert()
    {:ok, _} = ExternalIds.put(:tmdb, series, tmdb_id)
    series
  end

  defp seed_movie_series_with_tmdb!(attrs, tmdb_id) when is_map(attrs) do
    {:ok, series} = attrs |> MovieSeries.create_changeset() |> Repo.insert()
    {:ok, _} = ExternalIds.put(:tmdb_collection, series, tmdb_id)
    series
  end

  defp reload_with_external_ids!(schema, id) do
    Repo.preload(Repo.get!(schema, id), :external_ids)
  end

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Review.list_pending_files()

      Maintenance.clear_database()

      assert [] = Review.list_pending_files()
    end

    test "destroys PlayableItem rows (Library Schema v2 Phase 2 leaf)" do
      # PlayableItem was introduced in Phase 2 as the canonical leaf.
      # `resources_in_delete_order/0` must include it — otherwise
      # `clear_database/0` leaves orphan PlayableItems referencing
      # containers that have been deleted.
      movie = create_standalone_movie(%{name: "Doomed Movie"})
      create_playable_item_for_movie(movie)

      assert Repo.aggregate(PlayableItem, :count) == 1

      Maintenance.clear_database()

      assert Repo.aggregate(PlayableItem, :count) == 0
    end
  end

  describe "refresh_movie_credits/0" do
    setup [:setup_tmdb_client]

    test "populates cast, crew, and imdb_id on movies with empty credits and a tmdb_id" do
      movie = seed_movie_with_tmdb!(%{name: "Sample Movie", cast: [], crew: []}, "123")

      stub_get_movie("123", %{
        "imdb_id" => "tt0000123",
        "credits" => %{
          "cast" => [
            %{
              "name" => "Sample Actor",
              "character" => "Sample Role",
              "id" => 7,
              "profile_path" => "/p.jpg",
              "order" => 0
            }
          ],
          "crew" => [
            %{
              "id" => 9,
              "name" => "Sample Director",
              "department" => "Directing",
              "job" => "Director",
              "profile_path" => "/d.jpg"
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()

      reloaded = reload_with_external_ids!(Movie, movie.id)

      assert ExternalIds.get(reloaded, :imdb) == "tt0000123"

      assert [
               %Person{
                 name: "Sample Actor",
                 character: "Sample Role",
                 tmdb_person_id: 7,
                 profile_path: "/p.jpg",
                 order: 0
               }
             ] = reloaded.cast

      assert [
               %Person{
                 tmdb_person_id: 9,
                 name: "Sample Director",
                 job: "Director",
                 department: "Directing",
                 profile_path: "/d.jpg"
               }
             ] = reloaded.crew
    end

    test "skips movies that already have non-empty cast and crew" do
      existing_cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      existing_crew = [
        %{
          "tmdb_person_id" => 2,
          "name" => "Existing Director",
          "job" => "Director",
          "department" => "Directing",
          "profile_path" => nil
        }
      ]

      seed_movie_with_tmdb!(
        %{name: "Sample Movie", cast: existing_cast, crew: existing_crew},
        "456"
      )

      assert {:ok, %{updated: 0, skipped: 1, failed: 0}} = Maintenance.refresh_movie_credits()
    end

    test "refetches a movie that has cast but no crew" do
      cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      seed_movie_with_tmdb!(%{name: "Sample Movie", cast: cast, crew: []}, "789")

      stub_get_movie("789", %{
        "imdb_id" => "tt0000789",
        "credits" => %{
          "cast" => cast,
          "crew" => [
            %{
              "id" => 9,
              "name" => "Sample Director",
              "department" => "Directing",
              "job" => "Director",
              "profile_path" => nil
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()
    end

    test "skips movies without a tmdb_id" do
      # No `ExternalIds.put` call — movie has no TMDB external_id row.
      {:ok, _} =
        %{name: "Sample Movie", cast: [], crew: []}
        |> Movie.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()
    end
  end

  describe "refresh_series_credits/0" do
    setup [:setup_tmdb_client]

    test "populates cast, crew, and imdb_id on series with empty credits and a tmdb_id" do
      series = seed_tv_series_with_tmdb!(%{name: "Sample Series", cast: [], crew: []}, "200")

      stub_get_tv("200", %{
        "external_ids" => %{"imdb_id" => "tt0000200"},
        "created_by" => [
          %{"id" => 11, "name" => "Sample Creator", "profile_path" => "/c.jpg"}
        ],
        "aggregate_credits" => %{
          "cast" => [
            %{
              "id" => 7,
              "name" => "Sample Actor",
              "profile_path" => "/p.jpg",
              "order" => 0,
              "roles" => [%{"character" => "Sample Role", "episode_count" => 50}]
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_series_credits()

      reloaded = reload_with_external_ids!(TVSeries, series.id)

      assert ExternalIds.get(reloaded, :imdb) == "tt0000200"

      assert [
               %Person{
                 name: "Sample Actor",
                 character: "Sample Role",
                 tmdb_person_id: 7,
                 profile_path: "/p.jpg",
                 order: 0
               }
             ] = reloaded.cast

      assert [
               %Person{
                 tmdb_person_id: 11,
                 name: "Sample Creator",
                 job: "Creator",
                 department: "Creator",
                 profile_path: "/c.jpg"
               }
             ] = reloaded.crew
    end

    test "skips series that already have non-empty cast and crew" do
      existing_cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      existing_crew = [
        %{
          "tmdb_person_id" => 2,
          "name" => "Existing Creator",
          "job" => "Creator",
          "department" => "Creator",
          "profile_path" => nil
        }
      ]

      seed_tv_series_with_tmdb!(
        %{name: "Sample Series", cast: existing_cast, crew: existing_crew},
        "201"
      )

      assert {:ok, %{updated: 0, skipped: 1, failed: 0}} = Maintenance.refresh_series_credits()
    end

    test "refetches a series that has cast but no crew" do
      cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      seed_tv_series_with_tmdb!(%{name: "Sample Series", cast: cast, crew: []}, "202")

      stub_get_tv("202", %{
        "external_ids" => %{"imdb_id" => "tt0000202"},
        "created_by" => [%{"id" => 11, "name" => "Sample Creator", "profile_path" => nil}],
        "aggregate_credits" => %{"cast" => []}
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_series_credits()
    end

    test "skips series without a tmdb_id" do
      {:ok, _} =
        %{name: "Sample Series", cast: [], crew: []}
        |> TVSeries.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 0, failed: 0}} = Maintenance.refresh_series_credits()
    end
  end

  describe "refresh_movie_series_credits/0" do
    setup [:setup_tmdb_client]

    test "writes empty cast/crew (collection payload carries no top-level credits)" do
      series = seed_movie_series_with_tmdb!(%{name: "Sample Collection", cast: [], crew: []}, "263")

      stub_get_collection("263", %{
        "id" => 263,
        "name" => "Sample Collection",
        "overview" => "Sample overview.",
        "parts" => []
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} =
               Maintenance.refresh_movie_series_credits()

      reloaded = Repo.get!(MovieSeries, series.id)
      assert reloaded.cast == []
      assert reloaded.crew == []
    end

    test "skips collections that already have non-empty cast and crew" do
      existing_cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      existing_crew = [
        %{
          "tmdb_person_id" => 2,
          "name" => "Existing Director",
          "job" => "Director",
          "department" => "Directing",
          "profile_path" => nil
        }
      ]

      seed_movie_series_with_tmdb!(
        %{name: "Sample Collection", cast: existing_cast, crew: existing_crew},
        "264"
      )

      assert {:ok, %{updated: 0, skipped: 1, failed: 0}} =
               Maintenance.refresh_movie_series_credits()
    end

    test "skips collections without a tmdb_id" do
      {:ok, _} =
        %{name: "Sample Collection", cast: [], crew: []}
        |> MovieSeries.create_changeset()
        |> Repo.insert()

      assert {:ok, %{updated: 0, skipped: 0, failed: 0}} =
               Maintenance.refresh_movie_series_credits()
    end

    test "writes update via Person.put_credits even though MovieSeries has no imdb_id field" do
      # Person.put_credits/2 historically cast :imdb_id on the parent
      # schema. MovieSeries has no such column — the helper must skip
      # the field silently rather than raise. Without that guard this
      # call would crash inside `Ecto.Changeset.cast/3`.
      # After Library Schema v2 Phase 1 Task 6 the introspection is
      # gone, but the test stays as a regression guard against future
      # `:imdb_id` plumbing creep.
      seed_movie_series_with_tmdb!(%{name: "Sample Collection", cast: [], crew: []}, "265")

      stub_get_collection("265", %{
        "id" => 265,
        "name" => "Sample Collection",
        "overview" => "Sample overview.",
        "parts" => []
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} =
               Maintenance.refresh_movie_series_credits()
    end
  end
end
