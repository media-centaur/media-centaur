defmodule MediaCentaur.MaintenanceTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library.{
    ExternalIds,
    FilePresence,
    Movie,
    Person,
    PlayableItem,
    TVSeries
  }

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Events.EntitiesChanged
  alias MediaCentaur.Maintenance
  alias MediaCentaur.Repo
  alias MediaCentaur.Review

  import MediaCentaur.TestFactory
  import MediaCentaur.TmdbStubs

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

    test "destroys FilePresence rows so a post-clear scan re-detects files on disk" do
      # FilePresence is the scan's skip-ledger: the watcher startup scan
      # skips any path already in `FilePresence.list_paths_for_media_dir/1`
      # (watcher.ex). `clear_database/0` deletes the child WatchedFile rows
      # but the presence reference is a plain column (no DB cascade), so the
      # FilePresence parent rows survived — leaving a poisoned ledger that
      # made the post-clear watcher restart skip every file still on disk.
      # That is the "I cleared everything and it still won't pick up my
      # media" report: clearing must wipe the ledger so a rescan rebuilds
      # the library from disk.
      movie = create_standalone_movie(%{name: "Moved Movie"})

      file =
        create_linked_file(%{
          movie_id: movie.id,
          media_dir: "/media/test",
          file_path: "/media/test/sample.mkv"
        })

      assert file.file_path in FilePresence.list_paths_for_media_dir("/media/test")

      Maintenance.clear_database()

      assert Enum.empty?(FilePresence.list_paths_for_media_dir("/media/test"))
      assert Repo.aggregate(FilePresence, :count) == 0
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

    test "restores scalar metadata dropped by the old collection-child import path" do
      movie =
        seed_movie_with_tmdb!(
          %{name: "Sample Movie Two", cast: [], crew: [], genres: []},
          "321"
        )

      stub_get_movie(
        "321",
        movie_detail(%{
          "id" => 321,
          "title" => "Sample Movie Two",
          "status" => "Released",
          "vote_count" => 4321,
          "tagline" => "A sample tagline.",
          "original_language" => "en",
          "production_companies" => [%{"name" => "Sample Studio"}],
          "production_countries" => [%{"iso_3166_1" => "US"}],
          "credits" => %{
            "cast" => [
              %{
                "name" => "Sample Actor",
                "character" => "Lead",
                "id" => 7,
                "profile_path" => nil,
                "order" => 0
              }
            ],
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
      )

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_movie_credits()

      reloaded = Repo.get!(Movie, movie.id)
      assert reloaded.genres == ["Drama"]
      assert reloaded.status == :released
      assert reloaded.vote_count == 4321
      assert reloaded.tagline == "A sample tagline."
      assert reloaded.original_language == "en"
      assert reloaded.studio == "Sample Studio"
      assert reloaded.country_code == "US"
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

    test "broadcasts entities_changed for updated movies so the detail cache rebuilds" do
      # The ETS-backed Detail projection (read by the movie modal via
      # load_modal_entry/1) only rebuilds on {:entities_changed, _}. A
      # credit refresh that writes cast/crew but stays silent leaves the
      # modal showing a stale, cast-less projection — the bug this guards.
      movie = seed_movie_with_tmdb!(%{name: "Sample Movie", cast: [], crew: []}, "321")

      stub_get_movie("321", %{
        "imdb_id" => "tt0000321",
        "credits" => %{
          "cast" => [%{"name" => "Sample Actor", "character" => "Sample Role", "id" => 7, "order" => 0}],
          "crew" => [
            %{"id" => 9, "name" => "Sample Director", "department" => "Directing", "job" => "Director"}
          ]
        }
      })

      Library.subscribe()

      assert {:ok, %{updated: 1}} = Maintenance.refresh_movie_credits()

      assert_receive {:entities_changed, %EntitiesChanged{entity_ids: entity_ids}}
      assert movie.id in entity_ids
    end

    test "does not broadcast when no movie credits change" do
      seed_movie_with_tmdb!(
        %{
          name: "Sample Movie",
          cast: [%{"name" => "Existing", "tmdb_person_id" => 1, "order" => 0}],
          crew: [
            %{
              "tmdb_person_id" => 2,
              "name" => "Existing Director",
              "job" => "Director",
              "department" => "Directing"
            }
          ]
        },
        "654"
      )

      Library.subscribe()

      assert {:ok, %{updated: 0, skipped: 1}} = Maintenance.refresh_movie_credits()

      refute_receive {:entities_changed, _}
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

    test "skips series that already have counted cast and crew" do
      existing_cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0,
          "total_episode_count" => 62
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

    test "refetches a series whose cast predates appearance counts" do
      # Cast and crew are present, but every entry has a nil
      # total_episode_count — written before the column existed. The
      # skip predicate must treat that as stale.
      cast = [
        %{
          "name" => "Existing",
          "character" => "Existing",
          "tmdb_person_id" => 1,
          "profile_path" => nil,
          "order" => 0
        }
      ]

      crew = [
        %{
          "tmdb_person_id" => 2,
          "name" => "Existing Creator",
          "job" => "Creator",
          "department" => "Creator",
          "profile_path" => nil
        }
      ]

      series = seed_tv_series_with_tmdb!(%{name: "Sample Series", cast: cast, crew: crew}, "203")

      stub_get_tv("203", %{
        "external_ids" => %{"imdb_id" => "tt0000203"},
        "created_by" => [%{"id" => 2, "name" => "Existing Creator", "profile_path" => nil}],
        "aggregate_credits" => %{
          "cast" => [
            %{
              "id" => 1,
              "name" => "Existing",
              "profile_path" => nil,
              "order" => 0,
              "total_episode_count" => 48,
              "roles" => [%{"character" => "Existing", "episode_count" => 48}]
            }
          ]
        }
      })

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_series_credits()

      reloaded = reload_with_external_ids!(TVSeries, series.id)
      assert [%Person{total_episode_count: 48}] = reloaded.cast
    end

    test "backfills per-episode cast membership from season credits" do
      series = seed_tv_series_with_tmdb!(%{name: "Sample Series", cast: [], crew: []}, "204")
      season = create_season(%{tv_series_id: series.id, season_number: 1})
      episode_one = create_episode(%{season_id: season.id, episode_number: 1, name: "Pilot"})
      episode_two = create_episode(%{season_id: season.id, episode_number: 2, name: "Second"})

      stub_get_tv_with_seasons(
        "204",
        %{
          "external_ids" => %{"imdb_id" => "tt0000204"},
          "created_by" => [%{"id" => 2, "name" => "Sample Creator", "profile_path" => nil}],
          "aggregate_credits" => %{
            "cast" => [
              %{
                "id" => 10,
                "name" => "Regular A",
                "profile_path" => nil,
                "order" => 0,
                "total_episode_count" => 2,
                "roles" => [%{"character" => "Char A", "episode_count" => 2}]
              }
            ]
          }
        },
        %{
          1 => %{
            "season_number" => 1,
            "credits" => %{"cast" => [%{"id" => 10, "name" => "Regular A", "order" => 0}]},
            "episodes" => [
              %{"episode_number" => 1, "guest_stars" => [%{"id" => 20, "name" => "Guest A"}]},
              %{"episode_number" => 2, "guest_stars" => []}
            ]
          }
        }
      )

      assert {:ok, %{updated: 1, skipped: 0, failed: 0}} = Maintenance.refresh_series_credits()

      assert Repo.get!(MediaCentaur.Library.Episode, episode_one.id).cast_person_ids == [10, 20]
      assert Repo.get!(MediaCentaur.Library.Episode, episode_two.id).cast_person_ids == [10]
    end
  end

  describe "rederive_extra_names/0" do
    test "heals a blank extra name and clears the blank count" do
      movie = create_movie(%{name: "Sample Movie"})

      blank =
        create_extra(%{
          movie_id: movie.id,
          name: nil,
          content_url: "/media/test/Sample Show - Season 01/Extras/Making Of.mkv"
        })

      assert Maintenance.blank_extra_names_count() == 1

      assert {:ok, %{scanned: 1, updated: 1, skipped: 0}} = Maintenance.rederive_extra_names()

      assert Repo.get!(Library.Extra, blank.id).name == "Making Of"
      assert Maintenance.blank_extra_names_count() == 0
    end
  end
end
