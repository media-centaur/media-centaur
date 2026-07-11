defmodule MediaCentaurWeb.Storybook.Incoming.Ledger do
  @moduledoc """
  The Recently-landed ledger — open borderless rows dissolving into
  the page bottom via a static CSS mask. Severity dot, title + status
  sentence, outcome, relative time; "Show earlier" grows it once;
  storage sits as the ambient foot line. With no rows and nothing
  hidden the component renders nothing at all.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitRow}

  def function, do: &MediaCentaurWeb.Components.Incoming.Ledger.ledger/1
  def render_source, do: :function
  def layout, do: :one_column

  @gib 1_073_741_824

  defp drives do
    [
      %{
        mount_point: "/mnt/media",
        device: "/dev/sda",
        total_bytes: 4000 * @gib,
        used_bytes: 1200 * @gib,
        usage_percent: 30,
        roles: [%{label: "Media dir", path: "/mnt/media"}]
      }
    ]
  end

  defp row(id, title, opts) do
    %PursuitRow{
      id: id,
      title: title,
      state: Keyword.fetch!(opts, :state),
      status: %CurrentAction{
        verb: Keyword.fetch!(opts, :verb),
        description: Keyword.fetch!(opts, :description),
        severity: Keyword.fetch!(opts, :severity)
      },
      updated_at: DateTime.add(DateTime.utc_now(), -Keyword.fetch!(opts, :hours_ago), :hour),
      season_number: opts[:season],
      episode_number: opts[:episode]
    }
  end

  defp terminal_mix do
    [
      row("ledger-demo-1", "Safety Last!",
        state: :satisfied,
        verb: "Done",
        description: "File landed and identity verified.",
        severity: :success,
        hours_ago: 2
      ),
      row("ledger-demo-2", "Sample Show",
        state: :satisfied,
        verb: "Done",
        description: "File landed and identity verified.",
        severity: :success,
        season: 2,
        episode: 4,
        hours_ago: 26
      ),
      row("ledger-demo-3", "A Trip to the Moon",
        state: :exhausted,
        verb: "Gave up",
        description: "Exhausted after 3 attempts.",
        severity: :error,
        hours_ago: 96
      ),
      row("ledger-demo-4", "The Cabinet of Dr. Caligari",
        state: :cancelled,
        verb: "Cancelled",
        description: "Pursuit cancelled.",
        severity: :info,
        hours_ago: 120
      )
    ]
  end

  defp expanded_mix do
    terminal_mix() ++
      [
        row("ledger-demo-5", "Nosferatu",
          state: :satisfied,
          verb: "Done",
          description: "File landed and identity verified.",
          severity: :success,
          hours_ago: 168
        ),
        row("ledger-demo-6", "Sample Show",
          state: :partial,
          verb: "Partially done",
          description: "Some of this pursuit landed; the rest didn't.",
          severity: :warning,
          season: 2,
          episode: 3,
          hours_ago: 312
        ),
        row("ledger-demo-7", "Sample Documentary",
          state: :exhausted,
          verb: "Gave up",
          description: "Exhausted after 5 attempts.",
          severity: :error,
          hours_ago: 408
        )
      ]
  end

  def variations do
    [
      %Variation{
        id: :terminal_mix,
        description:
          "Landed / failed / cancelled — collapsed cap with more behind \"Show earlier\", " <>
            "storage on the foot line. The last rows dissolve into the mask fade.",
        attributes: %{rows: terminal_mix(), hidden_count: 3, storage_drives: drives()}
      },
      %Variation{
        id: :expanded,
        description:
          "Grown once — older rows (including a partial landing) reveal into the fade; " <>
            ~s{"Show earlier" is gone (anything more is "View all history").},
        attributes: %{rows: expanded_mix(), hidden_count: 2, expanded: true, storage_drives: drives()}
      },
      %Variation{
        id: :no_storage_line,
        description: "No single healthy drive to summarise — the foot line drops away.",
        attributes: %{rows: terminal_mix(), hidden_count: 0}
      },
      %Variation{
        id: :empty_renders_nothing,
        description:
          "No terminal pursuits and nothing hidden — the component renders nothing at " <>
            "all (no empty box), even when storage data is present.",
        attributes: %{rows: [], hidden_count: 0, storage_drives: drives()}
      }
    ]
  end
end
