defmodule MediaCentaur.LastActivityTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaur.LastActivity

  describe "compute/1" do
    test "movie with no progress returns inserted_at" do
      inserted = ~U[2026-01-15 10:00:00Z]
      entity = build_entity(%{type: :movie, inserted_at: inserted, watch_progress: []})

      assert LastActivity.compute(entity) == inserted
    end

    test "movie with progress returns last_watched_at when newer" do
      inserted = ~U[2026-01-15 10:00:00Z]
      watched = ~U[2026-03-01 20:00:00Z]

      entity =
        build_entity(%{
          type: :movie,
          inserted_at: inserted,
          watch_progress: [build_progress(%{last_watched_at: watched})]
        })

      assert LastActivity.compute(entity) == watched
    end

    test "movie with progress returns inserted_at when newer than last_watched_at" do
      inserted = ~U[2026-03-01 20:00:00Z]
      watched = ~U[2026-01-15 10:00:00Z]

      entity =
        build_entity(%{
          type: :movie,
          inserted_at: inserted,
          watch_progress: [build_progress(%{last_watched_at: watched})]
        })

      assert LastActivity.compute(entity) == inserted
    end

    test "movie series returns newest across entity, child movies, extras, and progress" do
      newest = ~U[2026-03-04 12:00:00Z]

      entity =
        build_entity(%{
          type: :movie_series,
          inserted_at: ~U[2026-01-01 00:00:00Z],
          movies: [
            build_movie(%{inserted_at: ~U[2026-01-10 00:00:00Z]}),
            build_movie(%{inserted_at: newest})
          ],
          extras: [
            build_extra(%{inserted_at: ~U[2026-02-01 00:00:00Z]})
          ],
          watch_progress: [
            build_progress(%{last_watched_at: ~U[2026-02-15 00:00:00Z]})
          ]
        })

      assert LastActivity.compute(entity) == newest
    end

    test "tv series returns newest across entity, episodes, season extras, entity extras, and progress" do
      newest = ~U[2026-03-04 18:30:00Z]

      entity =
        build_entity(%{
          type: :tv_series,
          inserted_at: ~U[2026-01-01 00:00:00Z],
          seasons: [
            build_season(%{
              episodes: [
                build_episode(%{inserted_at: ~U[2026-02-01 00:00:00Z]}),
                build_episode(%{inserted_at: ~U[2026-02-15 00:00:00Z]})
              ],
              extras: [
                build_extra(%{inserted_at: newest})
              ]
            })
          ],
          extras: [
            build_extra(%{inserted_at: ~U[2026-01-20 00:00:00Z]})
          ],
          watch_progress: [
            build_progress(%{last_watched_at: ~U[2026-03-01 00:00:00Z]})
          ]
        })

      assert LastActivity.compute(entity) == newest
    end

    test "entity with nil inserted_at and no children returns nil" do
      entity =
        build_entity(%{
          type: :movie,
          inserted_at: nil,
          watch_progress: []
        })

      assert LastActivity.compute(entity) == nil
    end

    test "movie with extras returns newest extra inserted_at" do
      newest = ~U[2026-03-04 15:00:00Z]

      entity =
        build_entity(%{
          type: :movie,
          inserted_at: ~U[2026-01-01 00:00:00Z],
          extras: [
            build_extra(%{inserted_at: ~U[2026-02-01 00:00:00Z]}),
            build_extra(%{inserted_at: newest})
          ],
          watch_progress: []
        })

      assert LastActivity.compute(entity) == newest
    end

    test "movie with multiple progress records returns newest last_watched_at" do
      newest = ~U[2026-03-04 20:00:00Z]

      entity =
        build_entity(%{
          type: :movie,
          inserted_at: ~U[2026-01-01 00:00:00Z],
          watch_progress: [
            build_progress(%{last_watched_at: ~U[2026-02-01 00:00:00Z]}),
            build_progress(%{last_watched_at: newest}),
            build_progress(%{last_watched_at: ~U[2026-01-15 00:00:00Z]})
          ]
        })

      assert LastActivity.compute(entity) == newest
    end

    test "tv series where season extra is newest" do
      newest = ~U[2026-03-04 22:00:00Z]

      entity =
        build_entity(%{
          type: :tv_series,
          inserted_at: ~U[2026-01-01 00:00:00Z],
          seasons: [
            build_season(%{
              episodes: [
                build_episode(%{inserted_at: ~U[2026-01-15 00:00:00Z]})
              ],
              extras: [
                build_extra(%{inserted_at: newest})
              ]
            })
          ],
          extras: [
            build_extra(%{inserted_at: ~U[2026-02-01 00:00:00Z]})
          ],
          watch_progress: [
            build_progress(%{last_watched_at: ~U[2026-03-01 00:00:00Z]})
          ]
        })

      assert LastActivity.compute(entity) == newest
    end

    test "entity with nil watch_progress uses empty list" do
      inserted = ~U[2026-01-15 10:00:00Z]

      entity =
        build_entity(%{
          type: :movie,
          inserted_at: inserted,
          watch_progress: nil
        })

      assert LastActivity.compute(entity) == inserted
    end
  end
end
