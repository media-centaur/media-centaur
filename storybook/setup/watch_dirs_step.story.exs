defmodule MediaCentarrWeb.Storybook.Setup.WatchDirsStep do
  @moduledoc """
  Watch directories step in the Setup Tour. Distinct UX from the binary
  and integration steps — multi-entry list with add/remove instead of a
  single field.

  ## Contract shape

      attr :result, MediaCentarrWeb.Live.SetupLive.Probe.Result, required: true
      attr :title, :string, required: true
      attr :step_index, :integer, required: true
      attr :total_steps, :integer, required: true
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Live.SetupLive.Probe

  def function, do: &MediaCentarrWeb.Components.SetupSteps.watch_dirs_step/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :empty,
        description: "Fresh state — no directories configured.",
        attributes: %{
          title: "Watch directories",
          step_index: 1,
          total_steps: 6,
          result: %Probe.Result{
            id: :watch_dirs,
            status: :not_configured,
            detail: "No watch directories — the library will stay empty.",
            current_value: [],
            critical?: true
          }
        }
      },
      %Variation{
        id: :one_dir,
        description: "Single watch directory configured and reachable.",
        attributes: %{
          title: "Watch directories",
          step_index: 1,
          total_steps: 6,
          result: %Probe.Result{
            id: :watch_dirs,
            status: :ok,
            detail: "1 directory configured.",
            current_value: [%{"dir" => "/mnt/media/movies"}],
            critical?: true
          }
        }
      },
      %Variation{
        id: :several_dirs,
        description: "Multiple directories, all reachable.",
        attributes: %{
          title: "Watch directories",
          step_index: 1,
          total_steps: 6,
          result: %Probe.Result{
            id: :watch_dirs,
            status: :ok,
            detail: "3 directories configured.",
            current_value: [
              %{"dir" => "/mnt/media/movies"},
              %{"dir" => "/mnt/media/tv"},
              %{"dir" => "/mnt/extras/anime"}
            ],
            critical?: true
          }
        }
      },
      %Variation{
        id: :one_missing,
        description: "Some directories unreachable — partial warning.",
        attributes: %{
          title: "Watch directories",
          step_index: 1,
          total_steps: 6,
          result: %Probe.Result{
            id: :watch_dirs,
            status: :warning,
            detail: "1 of 2 watch directories unreachable.",
            current_value: [
              %{"dir" => "/mnt/media/movies"},
              %{"dir" => "/mnt/disconnected-drive/tv"}
            ],
            critical?: true
          }
        }
      },
      %Variation{
        id: :all_missing,
        description: "All directories unreachable — likely an unmounted drive.",
        attributes: %{
          title: "Watch directories",
          step_index: 1,
          total_steps: 6,
          result: %Probe.Result{
            id: :watch_dirs,
            status: :error,
            detail: "All 2 watch directories are unreachable.",
            current_value: [
              %{"dir" => "/mnt/disconnected-drive/movies"},
              %{"dir" => "/mnt/disconnected-drive/tv"}
            ],
            critical?: true
          }
        }
      }
    ]
  end
end
