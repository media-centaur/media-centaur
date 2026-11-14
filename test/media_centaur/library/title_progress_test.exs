defmodule MediaCentaur.Library.TitleProgressTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Library.TitleProgress

  defp items(count), do: for(number <- 1..count, do: %{id: "e#{number}", key: ["00001", pad(number)]})

  defp position(number, finished_at \\ ~U[2026-11-12 22:00:00Z]),
    do: %{order_key: ["00001", pad(number)], finished_at: finished_at}

  defp pad(number), do: String.pad_leading("#{number}", 5, "0")

  defp row(number, opts) do
    %{
      playable_item: %{container_type: :episode, container_id: "e#{number}"},
      completed: Keyword.get(opts, :completed, false),
      position_seconds: Keyword.get(opts, :position, 0.0),
      duration_seconds: Keyword.get(opts, :duration, 1300.0),
      last_watched_at: Keyword.get(opts, :at, ~U[2026-11-01 00:00:00Z])
    }
  end

  defp marked(range), do: for(number <- range, do: row(number, completed: true))

  describe "compute/3" do
    test "nothing watched: unstarted, the first item is next" do
      progress = TitleProgress.compute(items(3), nil, [])

      assert %{state: :unstarted, next: %{item_id: "e1", offset_seconds: +0.0}, before_next: 0, total: 3} =
               progress

      assert progress.last_watched_at == nil
      assert TitleProgress.percent(progress) == 0
    end

    test "an empty ordered set is unstarted with no next" do
      progress = TitleProgress.compute([], nil, [])
      assert %{state: :unstarted, next: nil, before_next: 0, total: 0} = progress
      assert TitleProgress.percent(progress) == 0
    end

    test "first pass: next is the item after the position" do
      progress = TitleProgress.compute(items(4), position(2), marked(1..2))
      assert %{state: :in_progress, next: %{item_id: "e3"}, before_next: 2, total: 4} = progress
      assert TitleProgress.percent(progress) == 50
    end

    test "second pass: every item is marked and next still follows the position" do
      progress = TitleProgress.compute(items(138), position(5), marked(1..138))
      assert %{state: :in_progress, next: %{item_id: "e6"}, before_next: 5, total: 138} = progress
    end

    test "the position at the final item is complete" do
      progress = TitleProgress.compute(items(3), position(3), marked(1..3))
      assert %{state: :complete, next: nil, before_next: 3, total: 3} = progress
      assert TitleProgress.percent(progress) == 100
    end

    test "a replay of an old item moves next there, even with unwatched items ahead" do
      assert %{next: %{item_id: "e2"}} = TitleProgress.compute(items(4), position(1), marked(1..3))
    end

    test "the position's own item was deleted: next is the first item after its key" do
      remaining = Enum.reject(items(5), &(&1.id in ["e1", "e2", "e3"]))

      assert %{state: :in_progress, next: %{item_id: "e4"}, before_next: 0, total: 2} =
               TitleProgress.compute(remaining, position(3), [])
    end

    test "a skipped item is not returned to" do
      rows = [row(1, completed: true), row(3, completed: true)]
      assert %{next: %{item_id: "e4"}} = TitleProgress.compute(items(4), position(3), rows)
    end

    test "a viewing newer than the position is resumed at its offset" do
      rows =
        marked(1..2) ++ [row(3, position: 600.0, duration: 1200.0, at: ~U[2026-11-13 09:00:00Z])]

      progress = TitleProgress.compute(items(4), position(2), rows)

      assert %{next: %{item_id: "e3", offset_seconds: 600.0, duration_seconds: 1200.0}} = progress
      assert TitleProgress.percent(progress) == 62
    end

    test "a viewing older than the position is not resumed, but keeps its offset when reached" do
      stale = row(3, position: 620.0, at: ~U[2026-09-27 00:00:00Z])

      assert %{next: %{item_id: "e3", offset_seconds: 620.0}} =
               TitleProgress.compute(items(4), position(2), [stale])

      assert %{next: %{item_id: "e2", offset_seconds: +0.0}} =
               TitleProgress.compute(items(4), position(1), [stale])
    end

    test "a viewing under 60 seconds changes nothing" do
      click = row(1, completed: true, position: 15.0, at: ~U[2026-11-13 09:00:00Z])

      assert %{next: %{item_id: "e4", offset_seconds: +0.0}} =
               TitleProgress.compute(items(4), position(3), [click | marked(2..3)])

      assert %{state: :unstarted, next: %{item_id: "e1", offset_seconds: +0.0}} =
               TitleProgress.compute(items(4), nil, [row(1, position: 15.0)])
    end

    test "of several viewings newer than the position, the newest is resumed" do
      rows = [
        row(1, position: 100.0, at: ~U[2026-11-13 09:00:00Z]),
        row(4, position: 200.0, at: ~U[2026-11-13 10:00:00Z])
      ]

      assert %{next: %{item_id: "e4"}} = TitleProgress.compute(items(4), position(2), rows)
    end

    test "with no position, a viewing is resumed ahead of the first unmarked item" do
      rows = [row(1, completed: true), row(3, position: 400.0)]

      assert %{state: :in_progress, next: %{item_id: "e3", offset_seconds: 400.0}, before_next: 2} =
               TitleProgress.compute(items(4), nil, rows)
    end

    test "a viewing with no timestamp is resumed only where there is no position" do
      undated = row(3, position: 400.0, at: nil)

      assert %{next: %{item_id: "e3"}, last_watched_at: nil} =
               TitleProgress.compute(items(4), nil, [undated])

      assert %{next: %{item_id: "e2"}} = TitleProgress.compute(items(4), position(1), [undated])
    end

    test "hand marks with no position: next is the first unmarked item" do
      assert %{state: :in_progress, next: %{item_id: "e3"}} =
               TitleProgress.compute(items(4), nil, marked(1..2))
    end

    test "every item hand-marked with no position is complete" do
      assert %{state: :complete, next: nil} = TitleProgress.compute(items(2), nil, marked(1..2))
    end

    test "hand marks do not move next once a position exists" do
      assert %{next: %{item_id: "e2"}} = TitleProgress.compute(items(4), position(1), marked(1..3))
    end

    test "rows for items outside the ordered set are ignored" do
      assert %{state: :unstarted} = TitleProgress.compute(items(2), nil, [row(9, completed: true)])
    end

    test "a single-item title: unstarted, in flight, complete" do
      single = [%{id: "e1", key: []}]
      assert %{state: :unstarted} = TitleProgress.compute(single, nil, [])

      assert %{state: :in_progress, next: %{offset_seconds: 300.0}} =
               TitleProgress.compute(single, nil, [row(1, position: 300.0)])

      assert %{state: :complete} = TitleProgress.compute(single, nil, [row(1, completed: true)])

      assert %{state: :in_progress} =
               TitleProgress.compute(single, nil, [row(1, completed: true, position: 300.0)])
    end

    test "last_watched_at is the newest of the position and any counting viewing" do
      rows = [row(3, position: 600.0, at: ~U[2026-11-13 09:00:00Z])]

      assert TitleProgress.compute(items(4), position(2), rows).last_watched_at ==
               ~U[2026-11-13 09:00:00Z]

      assert TitleProgress.compute(items(4), position(2), []).last_watched_at ==
               ~U[2026-11-12 22:00:00Z]
    end
  end

  describe "percent/1" do
    test "no title progress reads 0" do
      assert TitleProgress.percent(nil) == 0
    end

    test "next with no known duration counts only the items before it" do
      rows = marked(1..1) ++ [row(2, position: 600.0, duration: 0.0, at: ~U[2026-11-13 09:00:00Z])]
      progress = TitleProgress.compute(items(4), position(1), rows)
      assert TitleProgress.percent(progress) == 25
    end
  end

  # The measure's own cases, restated from the tests of the two modules it
  # replaced (the Continue Watching bar and the progress summary).
  describe "percent/1 on a value" do
    defp in_progress(before_next, total, offset_seconds, duration_seconds) do
      %TitleProgress{
        state: :in_progress,
        next: %{item_id: "next", offset_seconds: offset_seconds, duration_seconds: duration_seconds},
        before_next: before_next,
        total: total
      }
    end

    test "an empty ordered set reads 0" do
      assert TitleProgress.percent(%TitleProgress{state: :unstarted, before_next: 0, total: 0}) == 0
    end

    test "a movie half viewed reads 50" do
      assert TitleProgress.percent(in_progress(0, 1, 50.0, 100.0)) == 50
    end

    test "the fraction is truncated, never rounded up: 199 seconds of 10000 reads 1" do
      assert TitleProgress.percent(in_progress(0, 1, 199.0, 10_000.0)) == 1
    end

    test "five of ten items before next, and next half viewed, reads 55" do
      assert TitleProgress.percent(in_progress(5, 10, 500.0, 1000.0)) == 55
    end

    test "five of ten items before next, and next not started, reads 50" do
      assert TitleProgress.percent(in_progress(5, 10, 0.0, 1000.0)) == 50
    end

    test "a zero duration gives next no credit" do
      assert TitleProgress.percent(in_progress(2, 4, 500.0, 0.0)) == 50
    end

    test "an offset past the duration counts next as one whole item, no more" do
      assert TitleProgress.percent(in_progress(0, 2, 150.0, 100.0)) == 50
      assert TitleProgress.percent(in_progress(0, 1, 150.0, 100.0)) == 100
    end

    test "a complete title reads 100" do
      complete = %TitleProgress{state: :complete, next: nil, before_next: 3, total: 3}
      assert TitleProgress.percent(complete) == 100
    end
  end

  describe "ordered_set/1" do
    test "a TV series: its episodes with a file, in story order" do
      entity = %{
        type: :tv_series,
        seasons: [
          %{
            season_number: 1,
            episodes: [
              %{id: "b", episode_number: 2, content_url: "/tv/sample/S01E02.mkv"},
              %{id: "a", episode_number: 1, content_url: "/tv/sample/S01E01.mkv"},
              %{id: "c", episode_number: 3, content_url: nil}
            ]
          }
        ]
      }

      assert TitleProgress.ordered_set(entity) == [
               %{id: "a", key: ["00001", "00001"]},
               %{id: "b", key: ["00001", "00002"]}
             ]
    end

    test "a movie collection: its movies with a file, by release date" do
      entity = %{
        type: :movie_series,
        movies: [
          %{id: "b", date_published: ~D[2003-01-01], position: 1, content_url: "/movies/b.mkv"},
          %{id: "a", date_published: ~D[2001-01-01], position: 0, content_url: "/movies/a.mkv"}
        ]
      }

      assert TitleProgress.ordered_set(entity) == [
               %{id: "a", key: ["2001-01-01", "00000"]},
               %{id: "b", key: ["2003-01-01", "00001"]}
             ]
    end

    test "a single-item title is its one item when it has a file, else empty" do
      assert TitleProgress.ordered_set(%{type: :movie, id: "m", content_url: "/movies/m.mkv"}) ==
               [%{id: "m", key: []}]

      assert TitleProgress.ordered_set(%{type: :movie, id: "m", content_url: nil}) == []
    end

    test "for_entity/3 applies the rule to the entity's ordered set" do
      entity = %{type: :movie, id: "e1", content_url: "/movies/m.mkv"}

      assert %{state: :in_progress, next: %{item_id: "e1", offset_seconds: 300.0}, total: 1} =
               TitleProgress.for_entity(entity, nil, [row(1, position: 300.0)])
    end
  end
end
