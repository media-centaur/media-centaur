defmodule MediaCentaurWeb.Storybook.Acquisition.UnitBoard do
  @moduledoc """
  The coverage board: units as attempt threads — the one word list, the
  outcome line, the releases tried behind each row, season roll-ups with
  their counts, the single-unit thread row, and a worst-case
  board (30 episodes, three of them failed 48 times).
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard
  alias MediaCentaur.Acquisition.ViewModels.UnitBoard.{Attempt, Row}

  def function, do: &MediaCentaurWeb.Components.Acquisition.UnitBoard.unit_board/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :season_groups,
        description:
          "A multi-season series rolls units up into season groups — the header counts by word and hoists the shared release. Season 2 holds a unit that gave up and one that was cancelled, so it starts open; Season 1, all landed, starts closed.",
        attributes: %{
          vm: board("story-board-5", season_one() ++ season_two(), wanted: 6, satisfied: 3),
          on_change_target: "request_decision"
        }
      },
      %Variation{
        id: :attempts_open,
        description:
          "The same board with S02E02's attempts open: the cause sentence, then every release tried, newest first, with how each ended.",
        attributes: %{
          vm: board("story-board-5", season_one() ++ season_two(), wanted: 6, satisfied: 3),
          disclosures: MapSet.new(["unit-board-row-u-21"]),
          on_change_target: "request_decision"
        }
      },
      %Variation{
        id: :mid_flight,
        description:
          "A flat board (one season, under the roll-up threshold): a landed row, a row on its third release with the swap control, and a row that needs a pick.",
        attributes: %{
          vm:
            board(
              "story-board-3",
              [
                row("u-1", "Sample Show S01E01", :satisfied, 1,
                  release: "Sample.Show.S01E01.1080p.WEB-DL",
                  attempts: [landed("Sample.Show.S01E01.1080p.WEB-DL", 7_200)]
                ),
                row("u-2", "Sample Show S01E02", :active, 1,
                  release: "Sample.Show.S01E02.1080p.WEB-DL",
                  actionable?: true,
                  attempts: [
                    trying("Sample.Show.S01E02.1080p.WEB-DL", 600),
                    failed("Sample.Show.S01E02.720p.HDTV", 1_800),
                    failed("Sample.Show.S01E02.1080p.WEBRip", 3_600)
                  ]
                ),
                row("u-3", "Sample Show S01E03", :active, 1, awaiting_decision?: true)
              ],
              wanted: 3,
              satisfied: 1
            ),
          on_change_target: "request_decision"
        }
      },
      %Variation{
        id: :all_landed,
        description: "Every unit landed — the bar is full and every row reads Landed.",
        attributes: %{
          vm:
            board(
              "story-board-2",
              [
                row("u-1", "Sample Show S01E01", :satisfied, 1,
                  release: "Sample.Show.S01.1080p.WEB-DL",
                  attempts: [landed("Sample.Show.S01.1080p.WEB-DL", 86_400)]
                ),
                row("u-2", "Sample Show S01E02", :satisfied, 1,
                  release: "Sample.Show.S01.1080p.WEB-DL",
                  attempts: [landed("Sample.Show.S01.1080p.WEB-DL", 86_400)]
                )
              ],
              wanted: 2,
              satisfied: 2
            )
        }
      },
      %Variation{
        id: :single_thread,
        description:
          "A single film renders its one thread row too — no Coverage count or bar, the row carries the releases tried.",
        attributes: %{
          vm:
            board(
              "story-board-1",
              [
                row("u-1", "Sample Movie 2010", :active, nil,
                  release: "Sample.Movie.2010.1080p.WEB-DL",
                  actionable?: true,
                  attempts: [
                    trying("Sample.Movie.2010.1080p.WEB-DL", 300),
                    failed(
                      "Sample.Movie.2010.2160p.REMUX",
                      4_000,
                      "Repair failed, not enough repair blocks"
                    )
                  ]
                )
              ],
              wanted: 1,
              satisfied: 0
            ),
          disclosures: MapSet.new(["unit-board-row-u-1"]),
          on_change_target: "request_decision"
        }
      },
      %Variation{
        id: :large_board,
        description:
          "The worst case: five seasons, thirty episodes, three of Season 4's failed 48 times and were cancelled. Season 4 opens on its own; S04E01's 48 attempts are open.",
        attributes: %{
          vm: board("story-board-30", large_rows(), wanted: 30, satisfied: 27),
          disclosures: MapSet.new(["unit-board-row-u-41"])
        }
      }
    ]
  end

  @now ~U[2026-11-05 01:27:00Z]

  defp ago(seconds), do: DateTime.add(@now, -seconds, :second)

  defp attempt(title, outcome, seconds_ago, opts) do
    %Attempt{
      release_title: title,
      quality: Keyword.get(opts, :quality, "1080p"),
      size_bytes: Keyword.get(opts, :size_bytes),
      indexer: Keyword.get(opts, :indexer),
      started_at: ago(seconds_ago + 900),
      ended_at: if(outcome != :trying, do: ago(seconds_ago)),
      detail: Keyword.get(opts, :detail),
      outcome: outcome
    }
  end

  defp landed(title, seconds_ago),
    do: attempt(title, :landed, seconds_ago, size_bytes: 2_400_000_000, indexer: "ExampleIndexer")

  defp trying(title, seconds_ago), do: attempt(title, :trying, seconds_ago, [])

  defp failed(title, seconds_ago, detail \\ "Aborted, cannot be completed"),
    do: attempt(title, :failed, seconds_ago, detail: detail)

  defp abandoned(title, seconds_ago), do: attempt(title, :abandoned, seconds_ago, [])

  defp row(id, label, state, season, opts) do
    attempts = Keyword.get(opts, :attempts, [])

    %Row{
      id: id,
      label: label,
      state: state,
      season_number: season,
      release_title: Keyword.get(opts, :release),
      awaiting_decision?: Keyword.get(opts, :awaiting_decision?, false),
      actionable?: Keyword.get(opts, :actionable?, false),
      attempts: attempts,
      attempt_count: length(attempts)
    }
  end

  defp board(id, rows, opts) do
    %UnitBoard{
      pursuit_id: id,
      wanted: Keyword.fetch!(opts, :wanted),
      satisfied: Keyword.fetch!(opts, :satisfied),
      units: rows,
      groups: UnitBoard.group_rows(rows)
    }
  end

  defp season_one do
    for episode <- 1..3 do
      row("u-1#{episode}", "Sample Show S01E0#{episode}", :satisfied, 1,
        release: "Sample.Show.S01.1080p.WEB-DL",
        attempts: [landed("Sample.Show.S01.1080p.WEB-DL", 172_800)]
      )
    end
  end

  defp season_two do
    [
      row("u-21", "Sample Show S02E01", :exhausted, 2,
        attempts: for(n <- 1..4, do: failed("Sample.Show.S02E01.1080p.WEB-DL-GROUP#{n}", n * 900))
      ),
      row("u-22", "Sample Show S02E02", :satisfied, 2,
        release: "Sample.Show.S02E02.1080p.WEB-DL",
        attempts: [
          landed("Sample.Show.S02E02.1080p.WEB-DL", 3_600),
          failed("Sample.Show.S02E02.720p.HDTV", 7_200)
        ]
      ),
      row("u-23", "Sample Show S02E03", :cancelled, 2,
        attempts: [
          abandoned("Sample.Show.S02E03.1080p.WEB-DL", 60),
          failed("Sample.Show.S02E03.1080p.WEBRip", 960)
        ]
      )
    ]
  end

  defp large_rows do
    for season <- 1..5, episode <- 1..6 do
      id = "u-#{season}#{episode}"
      label = "S0#{season}E0#{episode} · Episode #{episode}"
      title = "Sample.Show.S0#{season}E0#{episode}.1080p.WEB-DL"

      cond do
        season == 4 and episode in [1, 4, 5] ->
          attempts =
            [abandoned(title, 0)] ++
              for(n <- 1..47, do: failed("Sample.Show.S04E0#{episode}.1080p.WEB-DL-GROUP#{n}", n * 900))

          row(id, label, :cancelled, season, attempts: attempts)

        season == 4 and episode == 2 ->
          row(id, label, :satisfied, season,
            release: title,
            attempts:
              [landed(title, 10_000)] ++
                for(
                  n <- 1..27,
                  do: failed("Sample.Show.S04E02.1080p.WEB-DL-GROUP#{n}", 10_000 + n * 900)
                )
          )

        true ->
          row(id, label, :satisfied, season,
            release: "Sample.Show.S0#{season}.1080p.WEB-DL",
            attempts: [landed("Sample.Show.S0#{season}.1080p.WEB-DL", 40_000 + season * 1_000)]
          )
      end
    end
  end
end
