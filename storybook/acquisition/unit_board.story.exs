defmodule MediaCentaurWeb.Storybook.Acquisition.UnitBoard do
  @moduledoc """
  Per-unit drill-down for a composite pursuit (ADR-055) — one row per
  unit with its state, covering release, and a per-unit change-target
  affordance. Renders nothing for single-unit boards, so every
  variation here is a multi-unit composite.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.UnitBoard

  def function, do: &MediaCentaurWeb.Components.Acquisition.UnitBoard.unit_board/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :mid_flight,
        description:
          "A collapsed brace-expansion mid-flight — landed, downloading, awaiting a decision, and failed units side by side.",
        attributes: %{
          vm: %UnitBoard{
            pursuit_id: "story-board-1",
            wanted: 4,
            satisfied: 1,
            units: [
              %UnitBoard.Row{
                id: "u-1",
                label: "Sample Show S01E01",
                state: :satisfied,
                release_title: "Sample.Show.S01E01.1080p.WEB-DL"
              },
              %UnitBoard.Row{
                id: "u-2",
                label: "Sample Show S01E02",
                state: :active,
                release_title: "Sample.Show.S01E02.1080p.WEB-DL",
                actionable?: true
              },
              %UnitBoard.Row{
                id: "u-3",
                label: "Sample Show S01E03",
                state: :active,
                awaiting_decision?: true
              },
              %UnitBoard.Row{
                id: "u-4",
                label: "Sample Show S01E04",
                state: :exhausted
              }
            ]
          },
          on_change_target: "change_target"
        }
      },
      %Variation{
        id: :all_landed,
        description: "Every unit satisfied — full progress bar, no actions.",
        attributes: %{
          vm: %UnitBoard{
            pursuit_id: "story-board-2",
            wanted: 2,
            satisfied: 2,
            units: [
              %UnitBoard.Row{
                id: "u-5",
                label: "Sample Show S01E01",
                state: :satisfied,
                release_title: "Sample.Show.S01E01.1080p.WEB-DL"
              },
              %UnitBoard.Row{
                id: "u-6",
                label: "Sample Show S01E02",
                state: :satisfied,
                release_title: "Sample.Show.S01E02.1080p.WEB-DL"
              }
            ]
          },
          on_change_target: "change_target"
        }
      },
      %Variation{
        id: :partial_outcome,
        description:
          "Terminal partial outcome — a satisfied unit beside a cancelled one; nothing left to act on.",
        attributes: %{
          vm: %UnitBoard{
            pursuit_id: "story-board-3",
            wanted: 2,
            satisfied: 1,
            units: [
              %UnitBoard.Row{
                id: "u-7",
                label: "Sample Show S01E01",
                state: :satisfied,
                release_title: "Sample.Show.S01E01.1080p.WEB-DL"
              },
              %UnitBoard.Row{
                id: "u-8",
                label: "Sample Show S01E02",
                state: :cancelled
              }
            ]
          },
          on_change_target: "change_target"
        }
      },
      %Variation{
        id: :single_unit_renders_nothing,
        description:
          "Single-unit boards render nothing — the pursuit's one thread is already the whole modal. (Intentionally blank preview.)",
        attributes: %{
          vm: %UnitBoard{
            pursuit_id: "story-board-4",
            wanted: 1,
            satisfied: 0,
            units: [
              %UnitBoard.Row{id: "u-9", label: "Sample Movie 2010", state: :active, actionable?: true}
            ]
          },
          on_change_target: "change_target"
        }
      }
    ]
  end
end
