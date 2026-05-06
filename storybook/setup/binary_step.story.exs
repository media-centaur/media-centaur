defmodule MediaCentarrWeb.Storybook.Setup.BinaryStep do
  @moduledoc """
  One step in the Setup Tour for an external binary dependency
  (currently `mpv` and `ffprobe`).

  ## Contract shape

      attr :result, MediaCentarrWeb.Live.SetupLive.Probe.Result, required: true
      attr :title, :string, required: true
      attr :binary_name, :string, required: true
      attr :step_index, :integer, required: true
      attr :total_steps, :integer, required: true

  Variations cover the four states the wizard renders:

  - `:ok` — path configured, executable found
  - `:not_executable` — path configured, file exists, not executable
  - `:missing_with_candidates` — configured path missing, but other paths
    were detected on disk → "Use this" affordances
  - `:missing_no_candidates` — nothing detected anywhere → install hint
  - `:not_configured` — fresh state, no path entered yet
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Live.SetupLive.Probe

  def function, do: &MediaCentarrWeb.Components.SetupSteps.binary_step/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :ok,
        description: "Path configured and executable found.",
        attributes: %{
          title: "mpv (media player)",
          binary_name: "mpv",
          step_index: 3,
          total_steps: 6,
          result: %Probe.Result{
            id: :mpv,
            status: :ok,
            detail: "Found and executable.",
            current_value: "/usr/bin/mpv",
            detected_candidates: ["/usr/bin/mpv"],
            critical?: false
          }
        }
      },
      %Variation{
        id: :not_executable,
        description: "File exists but lacks the exec bit.",
        attributes: %{
          title: "mpv (media player)",
          binary_name: "mpv",
          step_index: 3,
          total_steps: 6,
          result: %Probe.Result{
            id: :mpv,
            status: :error,
            detail: "File exists but is not executable: /usr/bin/mpv",
            current_value: "/usr/bin/mpv",
            detected_candidates: [],
            critical?: false
          }
        }
      },
      %Variation{
        id: :missing_with_candidates,
        description: "Configured path missing, but other candidates were detected.",
        attributes: %{
          title: "ffprobe (subtitle detection)",
          binary_name: "ffprobe",
          step_index: 4,
          total_steps: 6,
          result: %Probe.Result{
            id: :ffprobe,
            status: :error,
            detail: "Not found: /usr/bin/ffprobe",
            current_value: "/usr/bin/ffprobe",
            detected_candidates: ["/usr/local/bin/ffprobe", "/opt/homebrew/bin/ffprobe"],
            critical?: false
          }
        }
      },
      %Variation{
        id: :missing_no_candidates,
        description: "Nothing detected anywhere — install hint shown.",
        attributes: %{
          title: "ffprobe (subtitle detection)",
          binary_name: "ffprobe",
          step_index: 4,
          total_steps: 6,
          result: %Probe.Result{
            id: :ffprobe,
            status: :error,
            detail: "Not found: /usr/bin/ffprobe",
            current_value: "/usr/bin/ffprobe",
            detected_candidates: [],
            critical?: false
          }
        }
      },
      %Variation{
        id: :not_configured,
        description: "Fresh state — no path entered yet.",
        attributes: %{
          title: "ffprobe (subtitle detection)",
          binary_name: "ffprobe",
          step_index: 4,
          total_steps: 6,
          result: %Probe.Result{
            id: :ffprobe,
            status: :not_configured,
            detail: "Without ffprobe, embedded subtitles can't be detected.",
            current_value: nil,
            detected_candidates: ["/usr/bin/ffprobe"],
            critical?: false
          }
        }
      }
    ]
  end
end
