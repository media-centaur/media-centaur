defmodule MediaCentaurWeb.Storybook.Console.LogView do
  @moduledoc """
  Story for `<.log_view>` — log lines in a scroller, oldest at the top and the
  live edge at the bottom. The `LogFollow` hook pins the live edge on mount,
  so each preview opens scrolled to its newest line; scrolling up holds the
  view and shows the jump control. Covers the list form (the systemd journal)
  with and without the per-line component badge and timestamp, and every
  level's colour. The stream form is the console page's, exercised by its
  tests.
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Console.Entry

  def function, do: &MediaCentaurWeb.ConsoleComponents.log_view/1

  def render_source, do: :function

  # Fixed ids and timestamps — a storybook render must be byte-stable.
  defp line(id, level, component, message) do
    %Entry{
      id: id,
      timestamp: DateTime.add(~U[2026-09-17 10:00:00Z], id, :second),
      level: level,
      component: component,
      message: message
    }
  end

  # Enough rows to overflow the bounded height, so the follow is visible.
  defp lines do
    for id <- 1..30 do
      case rem(id, 10) do
        0 -> line(id, :error, :pipeline, "Artwork fetch failed (503) for Sample Show")
        5 -> line(id, :warning, :tmdb, "Retrying TMDB request in 30s")
        _ -> line(id, :info, :watcher, "Detected Sample.Show.S01E#{pad(id)}.1080p.WEB-DL.mkv")
      end
    end
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  def variations do
    [
      %Variation{
        id: :following,
        description: "Every level, with timestamps and component badges, bounded and following",
        attributes: %{id: "story-log-following", lines: lines(), class: "max-h-64"}
      },
      %Variation{
        id: :bare_rows,
        description:
          "No badge and no timestamp — the systemd journal, whose lines carry their own stamp",
        attributes: %{
          id: "story-log-bare",
          lines: lines(),
          show_component: false,
          show_timestamp: false,
          class: "max-h-64"
        }
      },
      %Variation{
        id: :short,
        description: "Fewer lines than the height holds — nothing to scroll",
        attributes: %{id: "story-log-short", lines: Enum.take(lines(), 3), class: "max-h-64"}
      }
    ]
  end
end
