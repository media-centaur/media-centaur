defmodule MediaCentarrWeb.Storybook.Acquisition.PursuitRow do
  @moduledoc """
  One row in the Downloads index. Each card consumes a typed
  `PursuitRow` ViewModel; this story constructs literals so the
  variations are decoupled from any DB or LiveView state.

  Three surfaces per card: title (with TV S/E suffix), one
  severity-colored status sentence, and an optional download footer
  when a queue item is paired.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarr.Acquisition.ViewModels.{CurrentAction, DownloadProgress, PursuitRow}

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
        description: "Each pursuit state with the status sentence it produces.",
        variations: [
          %Variation{
            id: :active,
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  season: 1,
                  episode: 3,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release (attempt 2).",
                    severity: :info
                  }
                ),
              density: :full
            }
          },
          %Variation{
            id: :needs_decision,
            attributes: %{
              vm:
                row(:needs_decision, "Sample Show",
                  season: 2,
                  episode: 1,
                  status: %CurrentAction{
                    verb: "Decision needed",
                    description: "Pick a release below.",
                    severity: :warning
                  }
                )
            }
          },
          %Variation{
            id: :satisfied,
            attributes: %{
              vm:
                row(:satisfied, "Public Domain Film 1923",
                  status: %CurrentAction{
                    verb: "Done",
                    description: "File landed and identity verified.",
                    severity: :success
                  }
                )
            }
          },
          %Variation{
            id: :exhausted,
            attributes: %{
              vm:
                row(:exhausted, "Movie A",
                  status: %CurrentAction{
                    verb: "Gave up",
                    description: "Exhausted after 4 attempts.",
                    severity: :error
                  }
                )
            }
          },
          %Variation{
            id: :cancelled,
            attributes: %{
              vm:
                row(:cancelled, "Movie B",
                  status: %CurrentAction{
                    verb: "Cancelled",
                    description: "Pursuit cancelled.",
                    severity: :info
                  }
                )
            }
          }
        ]
      },
      %VariationGroup{
        id: :title_axis,
        description: "How the title composes with season/episode metadata.",
        variations: [
          %Variation{
            id: :movie,
            description: "Movie pursuit — no S/E suffix.",
            attributes: %{
              vm:
                row(:active, "Sample Movie",
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release.",
                    severity: :info
                  }
                )
            }
          },
          %Variation{
            id: :tv_episode,
            description: "TV episode pursuit — title gets `S01E03` appended.",
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  season: 1,
                  episode: 3,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release.",
                    severity: :info
                  }
                )
            }
          },
          %Variation{
            id: :tv_season_pack,
            description: "TV season-pack pursuit — `Season 2` instead of `SxxExx`.",
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  season: 2,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release.",
                    severity: :info
                  }
                )
            }
          },
          %Variation{
            id: :long_title,
            description: "Long title clamps to a single line via `truncate`.",
            attributes: %{
              vm:
                row(
                  :active,
                  "An Extraordinarily Long Pursuit Title That Forces The Row Layout To Truncate Within The Available Space",
                  season: 1,
                  episode: 12,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release.",
                    severity: :info
                  }
                )
            }
          }
        ]
      },
      %VariationGroup{
        id: :download_footer,
        description:
          "When a queue item is paired, the download footer renders and the status sentence is hidden — the live state speaks for itself.",
        variations: [
          %Variation{
            id: :matched_downloading,
            attributes: %{
              vm:
                row(:active, "Sample Movie",
                  release_title: "Sample.Movie.2010.1080p.WEB-DL",
                  status: any_action()
                ),
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
              vm:
                row(:active, "Sample Show",
                  season: 1,
                  episode: 3,
                  release_title: "Sample.Show.S01E03.1080p.WEB-DL",
                  status: any_action()
                ),
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
              vm:
                row(:active, "Public Domain Film 1923",
                  release_title: "Public.Domain.Film.1923.1080p",
                  status: any_action()
                ),
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
              vm:
                row(:active, "Movie A",
                  release_title: "Movie.A.1080p",
                  status: any_action()
                ),
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
            description: "No matched torrent yet — status sentence shows.",
            attributes: %{
              vm:
                row(:active, "Movie B",
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release (attempt 1).",
                    severity: :info
                  }
                )
            }
          },
          %Variation{
            id: :no_match_stuck,
            description:
              "Target acquired but the file never appeared in the download client — the v0.54 case.",
            attributes: %{
              vm:
                row(:active, "Movie C",
                  release_title: "Movie.C.1080p",
                  target_status: :acquired,
                  status: %CurrentAction{
                    verb: "Waiting",
                    description: "Not visible in your download client.",
                    severity: :warning
                  }
                )
            }
          }
        ]
      },
      %VariationGroup{
        id: :density_axis,
        description:
          "Compact density renders a single dense line — title + severity-colored status, no state badge. Used when there's no paired download.",
        variations: [
          %Variation{
            id: :compact_active,
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  season: 2,
                  episode: 4,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release (attempt 4).",
                    severity: :info
                  }
                ),
              density: :compact
            }
          },
          %Variation{
            id: :compact_searching_with_countdown,
            description:
              "When the worker has scheduled the next snooze, PursuitStatus surfaces the countdown — driven by `target.next_attempt_at` (denormalised off Oban's scheduled_at).",
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  season: 2,
                  episode: 4,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Next attempt in 2h 15m (attempt 4).",
                    severity: :info
                  }
                ),
              density: :compact
            }
          },
          %Variation{
            id: :compact_needs_decision,
            attributes: %{
              vm:
                row(:needs_decision, "Sample Show",
                  season: 1,
                  episode: 7,
                  status: %CurrentAction{
                    verb: "Decision needed",
                    description: "Pick a release below.",
                    severity: :warning
                  }
                ),
              density: :compact
            }
          },
          %Variation{
            id: :compact_exhausted,
            attributes: %{
              vm:
                row(:exhausted, "Movie A",
                  status: %CurrentAction{
                    verb: "Gave up",
                    description: "Exhausted after 4 attempts.",
                    severity: :error
                  }
                ),
              density: :compact
            }
          },
          %Variation{
            id: :compact_cancelled,
            attributes: %{
              vm:
                row(:cancelled, "Movie B",
                  status: %CurrentAction{
                    verb: "Cancelled",
                    description: "Pursuit cancelled.",
                    severity: :info
                  }
                ),
              density: :compact
            }
          },
          %Variation{
            id: :compact_long_title,
            description: "Long title truncates from the right; status stays on one line.",
            attributes: %{
              vm:
                row(
                  :active,
                  "An Extraordinarily Long Pursuit Title That Forces The Row Layout To Truncate Within The Available Space",
                  season: 1,
                  episode: 12,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release.",
                    severity: :info
                  }
                ),
              density: :compact
            }
          },
          %Variation{
            id: :compact_unframed,
            description:
              "`framed={false}` — the row drops its own glass card to sit inside a parent container (used by `PursuitGroup` so the group is the one card and per-episode rows are flat dividers within it). Out of context it looks like bare text on the storybook gradient; the parent context is exercised via the `PursuitGroup` story.",
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  season: 2,
                  episode: 4,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release (attempt 4).",
                    severity: :info
                  }
                ),
              density: :compact,
              framed: false
            }
          }
        ]
      }
    ]
  end

  # Story helpers ----------------------------------------------------

  defp row(state, title, opts) do
    %PursuitRow{
      id: "story-#{state}-#{:erlang.phash2({state, title, opts})}",
      title: title,
      state: state,
      season_number: Keyword.get(opts, :season),
      episode_number: Keyword.get(opts, :episode),
      release_title: Keyword.get(opts, :release_title),
      target_status: Keyword.get(opts, :target_status),
      status: Keyword.fetch!(opts, :status)
    }
  end

  # Placeholder action for download-footer variations where the status
  # line is hidden anyway — keeps the VM enforce_keys satisfied without
  # implying anything about the status contents.
  defp any_action do
    %CurrentAction{verb: "Downloading", description: "—", severity: :info}
  end
end
