defmodule MediaCentaurWeb.Storybook.Status.PipelineWidget do
  @moduledoc "Storybook coverage for the Pipeline Activity widget (content + image pipeline stages)."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.pipeline_widget/1

  def render_source, do: :function

  defp idle_stage do
    %{
      status: :idle,
      throughput: 0.0,
      avg_duration_ms: nil,
      active_count: 0,
      last_error: nil
    }
  end

  defp empty_content_stats do
    %{
      queue_depth: 0,
      total_failed: 0,
      stages: %{
        parse: idle_stage(),
        search: idle_stage(),
        fetch_metadata: idle_stage(),
        ingest: idle_stage()
      }
    }
  end

  defp empty_image_stats do
    %{
      status: :idle,
      throughput: 0.0,
      avg_duration_ms: nil,
      active_count: 0,
      total_downloaded: 0,
      total_failed: 0,
      queue_depth: 0,
      last_error: nil
    }
  end

  def variations do
    [
      %Variation{
        id: :idle,
        attributes: %{
          content_stats: empty_content_stats(),
          image_stats: empty_image_stats(),
          retry_status: %{retrying_count: 0},
          pipeline_concurrency: 4,
          image_concurrency: 8
        }
      },
      %Variation{
        id: :active,
        attributes: %{
          content_stats: %{
            queue_depth: 12,
            total_failed: 1,
            stages: %{
              parse: %{
                status: :active,
                throughput: 2.5,
                avg_duration_ms: 120,
                active_count: 2,
                last_error: nil
              },
              search: idle_stage(),
              fetch_metadata: idle_stage(),
              ingest: idle_stage()
            }
          },
          image_stats: %{
            status: :active,
            throughput: 5.0,
            avg_duration_ms: 800,
            active_count: 3,
            total_downloaded: 42,
            total_failed: 0,
            queue_depth: 4,
            last_error: nil
          },
          retry_status: %{retrying_count: 2},
          pipeline_concurrency: 4,
          image_concurrency: 8
        }
      }
    ]
  end
end
