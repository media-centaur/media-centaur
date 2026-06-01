defmodule MediaCentaurWeb.Storybook.Health.SubsystemTile do
  @moduledoc """
  Story for the `<.subsystem_tile>` component — the Subsystem Health Board's
  identity unit. Covers the health-state matrix (ok / warning / error) and the
  selected state. Color appears only on the dot/accent — never as subsystem
  identity (Phase 4 design D7).
  """
  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.StatusLive.SubsystemView

  def function, do: &MediaCentaurWeb.HealthComponents.subsystem_tile/1

  defp view(component, label, glyph, state, error_count, warning_count) do
    %SubsystemView{
      component: component,
      label: label,
      glyph: glyph,
      state: state,
      error_count: error_count,
      warning_count: warning_count
    }
  end

  def variations do
    [
      %Variation{
        id: :healthy,
        attributes: %{view: view(:watcher, "Watcher", "hero-eye", :ok, 0, 0)}
      },
      %Variation{
        id: :warning,
        attributes: %{view: view(:tmdb, "Metadata", "hero-film", :warning, 0, 3)}
      },
      %Variation{
        id: :error,
        attributes: %{view: view(:pipeline, "Import", "hero-arrow-down-tray", :error, 2, 1)}
      },
      %Variation{
        id: :selected,
        attributes: %{
          view: view(:pipeline, "Import", "hero-arrow-down-tray", :error, 2, 1),
          selected: true
        }
      }
    ]
  end
end
