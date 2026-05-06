defmodule MediaCentarrWeb.Storybook.Setup.SummaryStep do
  @moduledoc """
  Summary step — the final step in the Setup Tour. Shows every
  probed component with a status glyph and an "Edit" patch back to
  that step.

  ## Contract shape

      attr :probes, :list, required: true       # list of Probe.Result
      attr :step_index, :integer, required: true
      attr :total_steps, :integer, required: true

  Variations cover the headline copy variants:

  - `:everything_ok` — every probe `:ok`. Headline says "Everything is configured."
  - `:critical_unmet` — TMDB or watch_dirs in `:error` / `:not_configured`. Headline calls out required-step count.
  - `:partial` — some probes ok, some optional ones unconfigured.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Live.SetupLive.Probe

  def function, do: &MediaCentarrWeb.Components.SetupSteps.summary_step/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :everything_ok,
        description: "Every probe configured and verified.",
        attributes: %{
          step_index: 8,
          total_steps: 8,
          probes: [
            %Probe.Result{
              id: :watch_dirs,
              status: :ok,
              detail: "2 directories configured.",
              critical?: true
            },
            %Probe.Result{id: :tmdb, status: :ok, detail: "API key configured.", critical?: true},
            %Probe.Result{id: :mpv, status: :ok, detail: "/usr/bin/mpv", critical?: false},
            %Probe.Result{id: :ffprobe, status: :ok, detail: "/usr/bin/ffprobe", critical?: false},
            %Probe.Result{id: :prowlarr, status: :ok, detail: "API key configured.", critical?: false},
            %Probe.Result{
              id: :download_client,
              status: :ok,
              detail: "Credentials configured.",
              critical?: false
            }
          ]
        }
      },
      %Variation{
        id: :critical_unmet,
        description: "Required steps still incomplete — TMDB + watch_dirs missing.",
        attributes: %{
          step_index: 8,
          total_steps: 8,
          probes: [
            %Probe.Result{
              id: :watch_dirs,
              status: :not_configured,
              detail: "No watch directories — the library will stay empty.",
              critical?: true
            },
            %Probe.Result{
              id: :tmdb,
              status: :not_configured,
              detail: "Without TMDB, no metadata will be fetched.",
              critical?: true
            },
            %Probe.Result{id: :mpv, status: :ok, detail: "/usr/bin/mpv", critical?: false},
            %Probe.Result{id: :ffprobe, status: :ok, detail: "/usr/bin/ffprobe", critical?: false},
            %Probe.Result{id: :prowlarr, status: :not_configured, detail: "Optional.", critical?: false},
            %Probe.Result{
              id: :download_client,
              status: :not_configured,
              detail: "Optional.",
              critical?: false
            }
          ]
        }
      },
      %Variation{
        id: :partial,
        description: "Required steps done, optional integrations skipped.",
        attributes: %{
          step_index: 8,
          total_steps: 8,
          probes: [
            %Probe.Result{
              id: :watch_dirs,
              status: :ok,
              detail: "1 directory configured.",
              critical?: true
            },
            %Probe.Result{id: :tmdb, status: :ok, detail: "API key configured.", critical?: true},
            %Probe.Result{id: :mpv, status: :ok, detail: "/usr/bin/mpv", critical?: false},
            %Probe.Result{
              id: :ffprobe,
              status: :error,
              detail: "Not found: /usr/bin/ffprobe",
              critical?: false
            },
            %Probe.Result{id: :prowlarr, status: :not_configured, detail: "Optional.", critical?: false},
            %Probe.Result{
              id: :download_client,
              status: :not_configured,
              detail: "Optional.",
              critical?: false
            }
          ]
        }
      }
    ]
  end
end
