defmodule MediaCentaurWeb.Storybook.Status.HttpWidget do
  @moduledoc "Storybook coverage for the Connections Activity widget (per-upstream request figures + recent-request feed)."
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.HttpClient.Stats

  def function, do: &MediaCentaurWeb.Components.StatusWidgets.Http.http_widget/1

  def render_source, do: :function

  defp seconds_ago(seconds), do: DateTime.add(DateTime.utc_now(), -seconds, :second)

  defp with_rows(overrides) do
    snapshot = Stats.empty_snapshot()

    %{
      snapshot
      | upstreams:
          Enum.map(snapshot.upstreams, fn row ->
            case Map.fetch(overrides, row.id) do
              {:ok, changes} -> deep_merge(row, changes)
              :error -> row
            end
          end)
    }
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, %{} = a, %{} = b -> deep_merge(a, b)
      _key, _a, b -> b
    end)
  end

  defp busy_snapshot do
    %{
      with_rows(%{
        tmdb: %{
          window: %{
            requests: 42,
            errors: 0,
            median_latency_ms: 180,
            cache: %{hit: 30, miss: 10, revalidate: 2, reload: 0}
          },
          session: %{requests: 912, errors: 3},
          last_success_at: seconds_ago(12)
        },
        tmdb_images: %{
          window: %{requests: 88, errors: 0, median_latency_ms: 240},
          session: %{requests: 2_140, errors: 1},
          last_success_at: seconds_ago(15)
        },
        prowlarr: %{
          window: %{requests: 6, errors: 0, median_latency_ms: 2_300},
          session: %{requests: 41, errors: 0},
          last_success_at: seconds_ago(300)
        },
        qbittorrent: %{
          window: %{requests: 60, errors: 0, median_latency_ms: 20},
          session: %{requests: 3_600, errors: 0},
          last_success_at: seconds_ago(5)
        },
        steam: %{
          window: %{requests: 2, errors: 0, median_latency_ms: 310, cache: %{hit: 1, miss: 1}},
          session: %{requests: 9, errors: 0},
          last_success_at: seconds_ago(1_200)
        }
      })
      | recent: [
          %{
            at: seconds_ago(5),
            upstream: :qbittorrent,
            method: :get,
            path: "/api/v2/sync/maindata",
            status: 200,
            error: nil,
            duration_ms: 18,
            cache: :uncached
          },
          %{
            at: seconds_ago(12),
            upstream: :tmdb,
            method: :get,
            path: "/3/tv/1396",
            status: 200,
            error: nil,
            duration_ms: 0,
            cache: :hit
          },
          %{
            at: seconds_ago(15),
            upstream: :tmdb_images,
            method: :get,
            path: "/t/p/original/sample.jpg",
            status: 200,
            error: nil,
            duration_ms: 240,
            cache: :uncached
          },
          %{
            at: seconds_ago(40),
            upstream: :tmdb,
            method: :get,
            path: "/3/search/tv",
            status: 200,
            error: nil,
            duration_ms: 210,
            cache: :miss
          }
        ]
    }
  end

  defp failing_snapshot do
    %{
      with_rows(%{
        tmdb: %{
          window: %{requests: 20, errors: 16, median_latency_ms: 15_000},
          session: %{requests: 300, errors: 16},
          last_success_at: seconds_ago(1_100),
          last_failure_at: seconds_ago(8)
        }
      })
      | recent: [
          %{
            at: seconds_ago(8),
            upstream: :tmdb,
            method: :get,
            path: "/3/movie/550",
            status: nil,
            error: "timeout",
            duration_ms: 15_000,
            cache: :miss
          },
          %{
            at: seconds_ago(30),
            upstream: :tmdb,
            method: :get,
            path: "/3/movie/551",
            status: 503,
            error: nil,
            duration_ms: 420,
            cache: :miss
          }
        ]
    }
  end

  def variations do
    [
      %Variation{
        id: :idle,
        description: "Fresh boot: every upstream at zero, no feed yet.",
        attributes: %{http_stats: Stats.empty_snapshot(), rate_limiter: %{used: 0, total: 30}}
      },
      %Variation{
        id: :busy,
        description:
          "An import in progress: TMDB mostly served from cache, artwork streaming, the download client polling.",
        attributes: %{http_stats: busy_snapshot(), rate_limiter: %{used: 12, total: 30}}
      },
      %Variation{
        id: :failing,
        description: "TMDB timing out: errors in red on the row and in the feed.",
        attributes: %{http_stats: failing_snapshot(), rate_limiter: %{used: 30, total: 30}}
      }
    ]
  end
end
