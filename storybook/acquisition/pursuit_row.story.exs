defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitRow do
  @moduledoc """
  One row in the activity zone of `/download`. Each row consumes a typed
  `PursuitRow` ViewModel; this story constructs literals so the variations
  are decoupled from any DB or LiveView state.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.{DownloadProgress, PursuitRow, TimelineEntry}

  def function, do: &MediaCentarrWeb.Components.Acquisition.PursuitRow.pursuit_row/1
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
      %VariationGroup{
        id: :state_axis,
        description: "Each pursuit state, with representative recent events",
        variations: [
          %Variation{
            id: :active,
            attributes: %{vm: row(:active, "Sample Movie", events_active())}
          },
          %Variation{
            id: :needs_decision,
            attributes: %{vm: row(:needs_decision, "Sample Show S01E03", events_stalled())}
          },
          %Variation{
            id: :satisfied,
            attributes: %{vm: row(:satisfied, "Public Domain Film 1923", events_satisfied())}
          },
          %Variation{
            id: :exhausted,
            attributes: %{vm: row(:exhausted, "Movie A", events_exhausted())}
          },
          %Variation{
            id: :cancelled,
            attributes: %{vm: row(:cancelled, "Movie B", events_cancelled())}
          }
        ]
      },
      %Variation{
        id: :no_events_yet,
        description: "Freshly-created pursuit with no recorded events",
        attributes: %{
          vm:
            row_struct(%{
              id: "fresh-id",
              title: "Brand New Pursuit",
              state: :active,
              origin: :auto,
              attempt_count: 0,
              recent_events: []
            })
        }
      },
      %Variation{
        id: :long_title,
        description: "Long title clamps to a single line via `truncate`",
        attributes: %{
          vm:
            row_struct(%{
              id: "long-id",
              title:
                "An Extraordinarily Long Pursuit Title That Forces The Row Layout To Truncate Within The Available Space",
              state: :active,
              origin: :manual,
              attempt_count: 1,
              recent_events: events_active()
            })
        }
      },
      %VariationGroup{
        id: :download_footer,
        description:
          "Downloads index footer. When `download` is nil, the footer derives a hint from `grab_status`.",
        variations: [
          %Variation{
            id: :matched_downloading,
            attributes: %{
              vm: matched_row("Sample Movie 2010", :grabbed),
              download: %DownloadProgress{
                state: :downloading,
                progress_pct: 42.0,
                size_bytes: 4_200_000_000,
                size_left_bytes: 2_400_000_000,
                eta: "12m",
                client: "qBittorrent"
              },
              queue_item_id: "hash-downloading"
            }
          },
          %Variation{
            id: :matched_stalled,
            attributes: %{
              vm: matched_row("Sample Show S01E03", :grabbed),
              download: %DownloadProgress{
                state: :stalled,
                progress_pct: 18.0,
                eta: nil,
                client: "qBittorrent"
              },
              queue_item_id: "hash-stalled"
            }
          },
          %Variation{
            id: :matched_queued,
            attributes: %{
              vm: matched_row("Public Domain Film 1923", :grabbed),
              download: %DownloadProgress{
                state: :queued,
                progress_pct: nil,
                eta: nil,
                client: "qBittorrent"
              },
              queue_item_id: "hash-queued"
            }
          },
          %Variation{
            id: :matched_error,
            attributes: %{
              vm: matched_row("Movie A", :grabbed),
              download: %DownloadProgress{
                state: :error,
                progress_pct: 7.0,
                eta: nil,
                client: "qBittorrent"
              },
              queue_item_id: "hash-error"
            }
          },
          %Variation{
            id: :no_match_searching,
            description: "No matched torrent yet — auto-grab is still searching",
            attributes: %{
              vm: matched_row("Movie B", :searching, release_title: nil)
            }
          },
          %Variation{
            id: :no_match_stuck,
            description:
              "Grab nominally succeeded but the file never appeared in the download client (the v0.54.0 case)",
            attributes: %{
              vm: matched_row("Movie C", :grabbed)
            }
          }
        ]
      }
    ]
  end

  defp matched_row(title, grab_status, opts \\ []) do
    release_title = Keyword.get(opts, :release_title, "#{title}.1080p.WEB-DL")

    row_struct(%{
      id: "matched-#{grab_status}-#{:erlang.phash2(title)}",
      title: title,
      state: :active,
      origin: :auto,
      attempt_count: 1,
      recent_events: events_active(),
      release_title: release_title,
      grab_status: grab_status
    })
  end

  defp row(state, title, events) do
    row_struct(%{
      id: "story-#{state}",
      title: title,
      state: state,
      origin: if(state == :cancelled, do: :manual, else: :auto),
      attempt_count: attempts_for(state),
      recent_events: events
    })
  end

  defp row_struct(overrides) do
    struct!(
      %PursuitRow{
        id: "story-id",
        title: "Title",
        state: :active,
        origin: :auto,
        attempt_count: 0,
        recent_events: [],
        detail_path: "/download/story-id"
      },
      Map.put(overrides, :detail_path, "/download/#{overrides.id}")
    )
  end

  defp attempts_for(:active), do: 1
  defp attempts_for(:needs_decision), do: 2
  defp attempts_for(:satisfied), do: 1
  defp attempts_for(:exhausted), do: 4
  defp attempts_for(:cancelled), do: 1

  defp now, do: DateTime.utc_now(:second)
  defp ago(seconds), do: DateTime.add(now(), -seconds)

  defp events_active do
    [
      entry("release_picked", "Release picked — Sample.Movie.2010.1080p.WEB-DL", :success, ago(60)),
      entry("search_started", "Searching Prowlarr", :info, ago(120)),
      entry("pursuit_started", "Pursuit started (auto)", :info, ago(180))
    ]
  end

  defp events_stalled do
    [
      entry("user_decision_requested", "User decision requested", :info, ago(30)),
      entry("stall_confirmed", "Stall confirmed", :warning, ago(60)),
      entry("release_picked", "Release picked — Sample.Show.S01E03", :success, ago(7200))
    ]
  end

  defp events_satisfied do
    [
      entry("pursuit_satisfied", "Pursuit satisfied", :success, ago(45)),
      entry("identity_verified", "Identity verified", :success, ago(60)),
      entry("download_started", "Download started", :info, ago(3600))
    ]
  end

  defp events_exhausted do
    [
      entry("pursuit_exhausted", "Pursuit exhausted (max_attempts)", :error, ago(600)),
      entry("auto_cancelled", "Auto-cancelled (zero_seeders)", :warning, ago(1200)),
      entry("stall_confirmed", "Stall confirmed", :warning, ago(86_400))
    ]
  end

  defp events_cancelled do
    [
      entry("pursuit_cancelled", "Pursuit cancelled", :info, ago(120)),
      entry("user_decision_requested", "User decision requested", :info, ago(180)),
      entry("pursuit_started", "Pursuit started (manual)", :info, ago(240))
    ]
  end

  defp entry(kind, summary, severity, occurred_at) do
    %TimelineEntry{
      kind: kind,
      occurred_at: occurred_at,
      summary: summary,
      severity: severity
    }
  end
end
