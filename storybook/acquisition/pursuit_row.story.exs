defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitRow do
  @moduledoc """
  One row in the Downloads index. Each card consumes a typed
  `PursuitRow` ViewModel; this story constructs literals so the
  variations are decoupled from any DB or LiveView state.

  Three surfaces per card: title (with TV S/E suffix), one
  severity-colored status sentence, and an optional download strip
  when a queue item is paired.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, DownloadProgress, PursuitRow}
  alias MediaCentaur.Downloads.{Phase, QueueItem}

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitRow.pursuit_row/1
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
            id: :awaiting_decision,
            attributes: %{
              vm:
                row(:awaiting_decision, "Sample Show",
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
        id: :download_strip,
        description:
          "When a job is paired, the download strip renders and the status sentence is hidden — the live phase speaks for itself. Every phase lives in the Download strip story; this group covers the row's framing.",
        variations: [
          %Variation{
            id: :matched_downloading,
            attributes: %{
              vm:
                row(:active, "Sample Movie",
                  release_title: "Sample.Movie.2010.1080p.WEB-DL",
                  status: any_action()
                ),
              download:
                progress(:downloading,
                  title: "Sample.Movie.2010.1080p.WEB-DL",
                  progress_pct: 42.0,
                  size_bytes: 4_200_000_000,
                  size_left_bytes: 2_400_000_000,
                  eta: "12m",
                  client: "qBittorrent"
                ),
              queue_item_id: "hash-downloading"
            }
          },
          %Variation{
            id: :matched_downloading_stale,
            description:
              "Same download, but the client is lagging/offline — the live figures are qualified with a 'last seen' age so they don't read as real-time.",
            attributes: %{
              vm:
                row(:active, "Sample Movie",
                  release_title: "Sample.Movie.2010.1080p.WEB-DL",
                  status: any_action()
                ),
              download:
                progress(:downloading,
                  title: "Sample.Movie.2010.1080p.WEB-DL",
                  progress_pct: 42.0,
                  size_bytes: 4_200_000_000,
                  size_left_bytes: 2_400_000_000,
                  eta: "12m",
                  client: "qBittorrent"
                ),
              queue_item_id: "hash-downloading-stale",
              telemetry_age: "last seen 4m ago"
            }
          },
          %Variation{
            id: :matched_cancel_armed,
            description:
              "Cancel armed — the first click landed, so the strip's control relabels and turns " <>
                "danger. Deleting one torrent is recoverable by downloading it again, so it is " <>
                "the house arm gesture rather than an overlay (MC0027 tier 2). The control drops " <>
                "its circle shape here so the armed label has room.",
            attributes: %{
              vm:
                row(:active, "Sample Movie",
                  release_title: "Sample.Movie.2010.1080p.WEB-DL",
                  status: any_action()
                ),
              download:
                progress(:downloading,
                  title: "Sample.Movie.2010.1080p.WEB-DL",
                  progress_pct: 42.0,
                  size_bytes: 4_200_000_000,
                  size_left_bytes: 2_400_000_000,
                  eta: "12m",
                  client: "qBittorrent"
                ),
              queue_item_id: "hash-downloading",
              cancel_armed_id: "hash-downloading"
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
            id: :grabbing,
            description:
              "A release is chosen — by a person, a plan or the search — and the job that hands it to Prowlarr has not yet done so.",
            attributes: %{
              vm:
                row(:active, "Movie C",
                  release_title: "Movie.C.1080p",
                  target_status: :grabbing,
                  status: %CurrentAction{
                    verb: "Grabbing",
                    description: "Sending the chosen release to your download client.",
                    severity: :info
                  }
                )
            }
          },
          %Variation{
            id: :handed_off,
            description:
              "Just grabbed. Prowlarr accepted the release and the download client has not shown it yet — the seconds-to-a-minute window that used to read as \"Finished downloading\".",
            attributes: %{
              vm:
                row(:active, "Movie C",
                  release_title: "Movie.C.1080p",
                  target_status: :acquired,
                  status: %CurrentAction{
                    verb: "Grabbed",
                    description: "Waiting for your download client to pick it up.",
                    severity: :info
                  }
                )
            }
          },
          %Variation{
            id: :never_arrived,
            description:
              "Grabbed long enough ago that the client would have shown it. The grab was accepted but nothing arrived — the only warning-severity row with no live torrent behind it.",
            attributes: %{
              vm:
                row(:active, "Movie D",
                  release_title: "Movie.D.1080p",
                  target_status: :acquired,
                  status: %CurrentAction{
                    verb: "Not at your client",
                    description: "Prowlarr accepted the grab but the download never started.",
                    severity: :warning
                  }
                )
            }
          },
          %Variation{
            id: :downloaded_not_landed,
            description:
              "Seen at the download client and gone from it since, with no file in the library or review queue yet.",
            attributes: %{
              vm:
                row(:active, "Movie E",
                  release_title: "Movie.E.1080p",
                  target_status: :acquired,
                  status: %CurrentAction{
                    verb: "Downloaded",
                    description:
                      "Finished at your download client. Importing, or already in your library.",
                    severity: :info
                  }
                )
            }
          }
        ]
      },
      %VariationGroup{
        id: :identity_banners,
        description:
          "Title-doored pursuits (door: :media) render as identity banners (UIDR-014): per-title-hued scrimmed gradient, logotype title, semantic colors staying the brightest accents. Query-door pursuits keep plain rows — imagery means a title you chose.",
        variations: [
          %Variation{
            id: :media_movie_banner,
            description: "A TMDB-door movie pursuit — banner identity, state badge on the scrim.",
            attributes: %{
              vm:
                row(:active, "Night of the Living Dead",
                  door: :media,
                  status: %CurrentAction{
                    verb: "Searching",
                    description: "Looking for an acceptable release (attempt 1).",
                    severity: :info
                  }
                ),
              density: :full
            }
          },
          %Variation{
            id: :media_composite_banner,
            description:
              "A composite TMDB-door pursuit — segmented unit progress (landed / in flight / failed) instead of a bare percentage.",
            attributes: %{
              vm:
                row(:active, "Sample Show",
                  door: :media,
                  units_wanted: 13,
                  units_satisfied: 7,
                  unit_states:
                    List.duplicate("satisfied", 7) ++
                      List.duplicate("active", 4) ++ List.duplicate("exhausted", 2),
                  status: %CurrentAction{
                    verb: "Downloading",
                    description: "4 releases still in flight.",
                    severity: :info
                  }
                ),
              downloads: [
                %{
                  download:
                    progress(:downloading,
                      title: "Sample.Show.S01.1080p.WEB-DL-GROUP",
                      progress_pct: 76.0,
                      size_bytes: 14_500_000_000,
                      size_left_bytes: 3_500_000_000,
                      eta: "9m",
                      client: "qBittorrent"
                    ),
                  queue_item_id: "hash-s1-pack"
                },
                %{
                  download:
                    progress(:downloading,
                      title: "Sample.Show.S02.2160p.WEB-DL-GROUP",
                      progress_pct: 18.0,
                      size_bytes: 51_600_000_000,
                      size_left_bytes: 42_300_000_000,
                      eta: "1h 4m",
                      client: "qBittorrent"
                    ),
                  queue_item_id: "hash-s2-pack"
                }
              ],
              density: :full
            }
          },
          %Variation{
            id: :query_door_chip,
            description: "Query-door compact row — plain text plus the small door chip.",
            attributes: %{
              vm:
                row(:active, "Sample Show S01E{01-04}",
                  door: :query,
                  units_wanted: 4,
                  units_satisfied: 3,
                  status: %CurrentAction{
                    verb: "Downloading",
                    description: "1 release still in flight.",
                    severity: :info
                  }
                ),
              density: :compact
            }
          }
        ]
      },
      %VariationGroup{
        id: :composite_axis,
        description:
          "Composite pursuits (ADR-055) — a brace-expanded batch grab is one pursuit with many units. Rows show unit progress as a `N of M` chip; single-unit pursuits show no chip.",
        variations: [
          %Variation{
            id: :composite_active,
            description: "Multi-unit composite mid-flight — 3 of 10 units satisfied.",
            attributes: %{
              vm:
                row(:active, "Sample Show S01E{01-10}",
                  units_wanted: 10,
                  units_satisfied: 3,
                  status: %CurrentAction{
                    verb: "Downloading",
                    description: "7 releases still in flight.",
                    severity: :info
                  }
                ),
              density: :full
            }
          },
          %Variation{
            id: :composite_partial,
            description:
              "Terminal `partial` outcome — some units landed, the rest didn't. Buckets as success; badge tells the truth.",
            attributes: %{
              vm:
                row(:partial, "Sample Show S01E{01-10}",
                  units_wanted: 10,
                  units_satisfied: 7,
                  status: %CurrentAction{
                    verb: "Partially done",
                    description: "Some of this pursuit landed; the rest didn't.",
                    severity: :warning
                  }
                ),
              density: :full
            }
          },
          %Variation{
            id: :composite_compact,
            description: "Compact density keeps the unit-progress chip beside the status.",
            attributes: %{
              vm:
                row(:active, "Sample Show S01E{01-10}",
                  units_wanted: 10,
                  units_satisfied: 9,
                  status: %CurrentAction{
                    verb: "Downloading",
                    description: "1 release still in flight.",
                    severity: :info
                  }
                ),
              density: :compact
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
            id: :compact_awaiting_decision,
            attributes: %{
              vm:
                row(:awaiting_decision, "Sample Show",
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
      # The :awaiting_decision pseudo-state is sugar for stories — the
      # underlying VM state is :active with the awaiting flag set, so
      # the badge and grouping behave like a real awaiting pursuit.
      state: if(state == :awaiting_decision, do: :active, else: state),
      awaiting_decision?: state == :awaiting_decision,
      season_number: Keyword.get(opts, :season),
      episode_number: Keyword.get(opts, :episode),
      release_title: Keyword.get(opts, :release_title),
      target_status: Keyword.get(opts, :target_status),
      units_wanted: Keyword.get(opts, :units_wanted, 1),
      units_satisfied: Keyword.get(opts, :units_satisfied, 0),
      door: Keyword.get(opts, :door, :query),
      unit_states: Keyword.get(opts, :unit_states, []),
      status: Keyword.fetch!(opts, :status)
    }
  end

  # Placeholder action for download-strip variations where the status
  # line is hidden anyway — keeps the VM enforce_keys satisfied without
  # implying anything about the status contents.
  defp any_action do
    %CurrentAction{verb: "Downloading", description: "—", severity: :info}
  end

  # A DownloadProgress the way `QueueMatcher.to_download/1` builds one.
  defp progress(state, opts) do
    item = %QueueItem{
      id: "job",
      title: Keyword.get(opts, :title),
      status: Keyword.get(opts, :status),
      state: state,
      protocol: Keyword.get(opts, :protocol, :torrent),
      progress: Keyword.get(opts, :progress_pct),
      size: Keyword.get(opts, :size_bytes),
      timeleft: Keyword.get(opts, :eta)
    }

    %DownloadProgress{
      state: state,
      title: item.title,
      progress_pct: item.progress,
      size_bytes: item.size,
      size_left_bytes: Keyword.get(opts, :size_left_bytes),
      eta: item.timeleft,
      client: Keyword.get(opts, :client),
      protocol: item.protocol,
      phase: Phase.of(item)
    }
  end
end
