defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitActivity do
  @moduledoc "Live status card for the pursuit detail modal."

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Recipe

  alias MediaCentaur.Acquisition.ViewModels.{
    CurrentAction,
    DownloadProgress,
    NextStep,
    PursuitStatus
  }

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitActivity.pursuit_activity/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  defp base(overrides) do
    base = %PursuitStatus{
      pursuit_id: "story-pursuit",
      title: "Sample Movie",
      state: :active,
      origin: :auto,
      recipe: %Recipe{
        type: :tmdb,
        title: "Sample Movie",
        tmdb_type: :movie
      },
      search_queries: ["Sample Movie 2010"],
      current_action: %CurrentAction{
        verb: "Downloading",
        description: "Sample description.",
        severity: :info
      },
      available_actions: [:cancel],
      staleness: :fresh
    }

    struct(base, overrides)
  end

  def variations do
    [
      %Variation{
        id: :downloading_healthy,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Downloading",
                description: "From qBittorrent • 42% • ETA 8m",
                severity: :info
              },
              download: %DownloadProgress{
                state: :downloading,
                progress_pct: 42.0,
                client: "qBittorrent",
                eta: "8m"
              },
              next_step: %NextStep{
                description: "When complete, the file watcher matches the title."
              }
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :cancel_armed,
        attributes: %{
          cancel_armed: true,
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Downloading",
                description: "From qBittorrent • 42% • ETA 8m",
                severity: :info
              },
              download: %DownloadProgress{
                state: :downloading,
                progress_pct: 42.0,
                client: "qBittorrent",
                eta: "8m"
              },
              next_step: %NextStep{
                description: "When complete, the file watcher matches the title."
              }
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :downloading_stalled,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Stalled",
                description: "Download client can't make progress.",
                severity: :warning
              },
              download: %DownloadProgress{state: :stalled, progress_pct: 12.0},
              next_step: %NextStep{description: "Re-search for a different release, or wait."},
              available_actions: [:cancel, :change_target, :request_decision]
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop",
          on_change_target: "noop",
          on_request_decision: "noop"
        }
      },
      %Variation{
        id: :downloading_paused,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Paused",
                description: "Paused at the download client.",
                severity: :info
              },
              download: %DownloadProgress{state: :paused, progress_pct: 67.0},
              next_step: %NextStep{description: "Resume it in your download client."}
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :queued_at_client,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Queued",
                description: "Waiting for a slot at the download client.",
                severity: :info
              },
              download: %DownloadProgress{state: :queued},
              next_step: %NextStep{description: "Will start when a slot frees up."}
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :searching_prowlarr,
        description: "TV episode — actual queries shown under the verb",
        attributes: %{
          vm:
            base(
              recipe: %Recipe{
                type: :tmdb,
                title: "Sample Show",
                tmdb_type: :tv,
                season_number: 1,
                episode_number: 3
              },
              search_queries: ["Sample Show S01E03", "Sample Show Season 1"],
              current_action: %CurrentAction{
                verb: "Searching",
                description: "Looking for an acceptable release (attempt 2).",
                severity: :info
              },
              next_step: %NextStep{
                description: "Trying expanded queries — will pick the best match or snooze."
              }
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :seeking_between_attempts,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Seeking",
                description: "Waiting before the next search attempt.",
                severity: :info
              },
              next_step: %NextStep{description: "Will resume automatically."},
              available_actions: [:cancel, :change_target, :request_decision],
              staleness: :stale,
              last_activity_at: DateTime.add(DateTime.utc_now(:second), -3 * 3600, :second)
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop",
          on_change_target: "noop",
          on_request_decision: "noop"
        }
      },
      %Variation{
        id: :downloaded_not_landed,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Downloaded",
                description:
                  "Finished downloading — no file has landed in your library or review queue yet.",
                severity: :info
              },
              next_step: %NextStep{
                description:
                  "It may still be importing or already be in your library; change target to grab a different release."
              },
              available_actions: [:cancel, :change_target],
              staleness: :very_stale,
              last_activity_at: DateTime.add(DateTime.utc_now(:second), -2 * 86_400, :second)
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop",
          on_change_target: "noop"
        }
      },
      %Variation{
        id: :in_review,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "In review",
                description: "Downloaded — waiting for you to approve the match in Review.",
                severity: :info
              },
              next_step: %NextStep{
                description: "Approve it in the Review queue to finish importing."
              },
              available_actions: [:cancel],
              staleness: :stale,
              last_activity_at: DateTime.add(DateTime.utc_now(:second), -6 * 3600, :second)
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :download_complete_unmatched,
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Verifying",
                description: "Download finished — waiting for the file to be matched.",
                severity: :info
              },
              download: %DownloadProgress{state: :completed, progress_pct: 100.0},
              next_step: %NextStep{description: "InboundListener picks it up next."}
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :download_failed_at_client,
        description: "Client-reported terminal failure — the client's own message + open link",
        attributes: %{
          vm:
            base(
              current_action: %CurrentAction{
                verb: "Failed",
                description: "SABnzbd: Repair failed, not enough repair blocks",
                severity: :error
              },
              download: %DownloadProgress{state: :error, client: "SABnzbd", protocol: :usenet},
              next_step: %NextStep{
                description:
                  "A different release will be tried automatically — open SABnzbd for the job log."
              },
              available_actions: [:cancel, :change_target]
            ),
          client_url: "http://localhost:8085",
          on_cancel: "noop",
          on_cancel_arm: "noop",
          on_change_target: "noop"
        }
      },
      %Variation{
        id: :awaiting_decision,
        attributes: %{
          vm:
            base(
              state: :active,
              current_action: %CurrentAction{
                verb: "Decision needed",
                description: "Pick a release below.",
                severity: :warning
              },
              next_step: %NextStep{description: "Use the decision card below to pick or skip."}
            ),
          on_cancel: "noop",
          on_cancel_arm: "noop"
        }
      },
      %Variation{
        id: :terminal_satisfied,
        attributes: %{
          vm:
            base(
              state: :satisfied,
              current_action: %CurrentAction{
                verb: "Done",
                description: "File landed and identity verified.",
                severity: :success
              },
              next_step: nil,
              available_actions: []
            )
        }
      },
      %Variation{
        id: :terminal_exhausted,
        attributes: %{
          vm:
            base(
              state: :exhausted,
              current_action: %CurrentAction{
                verb: "Gave up",
                description: "Exhausted after 12 attempts.",
                severity: :error
              },
              next_step: %NextStep{description: "Start a new pursuit if you still want this."},
              available_actions: []
            )
        }
      },
      %Variation{
        id: :terminal_cancelled,
        attributes: %{
          vm:
            base(
              state: :cancelled,
              current_action: %CurrentAction{
                verb: "Cancelled",
                description: "Pursuit cancelled.",
                severity: :info
              },
              next_step: nil,
              available_actions: []
            )
        }
      }
    ]
  end
end
