defmodule MediaCentaurWeb.Storybook.Health.JournalPanel do
  @moduledoc """
  Story for the `<.journal_panel>` component — the systemd journal in the
  System drill-in's full-width logs row, a log view that follows its live
  edge. Covers collapsed (the resting state, and the only one that has not
  subscribed), expanded onto lines, and expanded before the tail has written
  anything.

  Reconnect rides the expanded states — it force-respawns `journalctl` when
  the tail dies under an open panel — so it has no variation of its own.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Console.Entry

  def function, do: &MediaCentaurWeb.HealthComponents.journal_panel/1

  def render_source, do: :function

  # Fixed ids and timestamps — a storybook render must be byte-stable. The
  # journal writes its own timestamp into the message; the entry's own stamp
  # is the arrival time and the panel does not render it.
  defp line(id, message) do
    %Entry{
      id: id,
      timestamp: ~U[2026-09-17 10:00:00Z],
      level: :info,
      component: :systemd,
      message: message
    }
  end

  defp row(inner), do: ~s|<div class="w-[48rem]">#{inner}</div>|

  def variations do
    [
      %Variation{
        id: :collapsed,
        description: "The resting state — nothing is subscribed and journalctl is not running",
        template: row("<.psb-variation/>"),
        attributes: %{open: false}
      },
      %Variation{
        id: :expanded,
        description: "Expanded onto the tail, oldest first, with Reconnect",
        template: row("<.psb-variation/>"),
        attributes: %{
          open: true,
          lines: [
            line(1, "2026-09-17T10:00:00+0200 host systemd[1]: Started Media Centaur."),
            line(2, "2026-09-17T10:00:02+0200 host media-centaur[9142]: Listening on port 2160"),
            line(3, "2026-09-17T10:00:04+0200 host media-centaur[9142]: Watcher scan complete")
          ]
        }
      },
      %Variation{
        id: :expanded_empty,
        description: "Expanded before the tail has written anything; Reconnect is still offered",
        template: row("<.psb-variation/>"),
        attributes: %{open: true, lines: []}
      }
    ]
  end
end
