defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitModal do
  @moduledoc """
  Pursuit detail modal — opened from the Activity zone when a pursuit
  row is clicked. A tenant of the cinematic modal frame
  (`CinematicShell`), so a pursued title reads as the same surface as
  one in the library: fixed backdrop, hero window, pinned identity
  lockup, with the work surface (facts / unit board / activity /
  decision card / timeline) as the scrolling body.

  Each variation passes `open: true|false` directly. Variations that
  start open wire `on_close` to a `psb-assign` event so closing the
  modal flips the variation's assigns rather than walking it out of the
  DOM.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Recipe

  alias MediaCentaur.Acquisition.ViewModels.{
    Alternative,
    CurrentAction,
    DecisionCard,
    DownloadProgress,
    NextStep,
    PursuitHeader,
    PursuitStatus,
    Timeline,
    TimelineEntry
  }

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitModal.pursuit_modal/1
  def render_source, do: :function
  def layout, do: :one_column

  # The component renders the cinematic frame — a real `position: fixed`
  # overlay — so variations would stack in a shared DOM. Iframing
  # isolates them (same treatment as the detail_panel story).
  def container, do: {:iframe, style: "min-height: 720px; width: 100%;"}

  def template do
    """
    <div>
      <button
        type="button"
        class="btn btn-sm btn-primary"
        phx-click={Phoenix.LiveView.JS.push("psb-assign", value: %{open: true})}
        psb-code-hidden
      >
        Open modal
      </button>
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :closed,
        description:
          "Closed — modal lives in the DOM but is hidden via `data-state=\"closed\"`. " <>
            "Click *Open modal* above to flip the variation's `open` assign and " <>
            "exercise the open transition.",
        attributes: %{open: false}
      },
      %Variation{
        id: :not_found,
        description:
          "Open with `not_found?` — the URL named a pursuit that no longer exists " <>
            "(deleted, or a stale link).",
        attributes: %{open: true, not_found?: true}
      },
      %Variation{
        id: :open_active_pursuit,
        description:
          "Open — active pursuit, downloading at 42%, no decision needed. Cached artwork " <>
            "dresses the frame: the backdrop paints the hero window and the logo PNG is " <>
            "the pinned lockup (inline SVG stand-ins; real assets come from /media-images).",
        attributes: %{
          open: true,
          pursuit_id: "story-active",
          header: active_movie_header(),
          status: downloading_status(),
          timeline: short_timeline(),
          on_close: close_event(:open_active_pursuit)
        }
      },
      %Variation{
        id: :open_awaiting_decision,
        description: "Open — pursuit awaiting user decision, with three alternatives.",
        attributes: %{
          open: true,
          pursuit_id: "story-decision",
          header: awaiting_decision_header(),
          status: awaiting_decision_status(),
          decision_card: many_alternatives(),
          timeline: stall_timeline(),
          on_close: close_event(:open_awaiting_decision)
        }
      },
      %Variation{
        id: :open_terminal_satisfied,
        description: "Open — satisfied pursuit (terminal). No actions; timeline reads success.",
        attributes: %{
          open: true,
          pursuit_id: "story-satisfied",
          header: satisfied_header(),
          status: satisfied_status(),
          timeline: stall_to_satisfied_timeline(),
          on_close: close_event(:open_terminal_satisfied)
        }
      },
      %Variation{
        id: :open_composite_pursuit,
        description:
          "Open — composite pursuit (ADR-055): the unit board renders between the header and the activity card, one row per unit with per-unit change-target.",
        attributes: %{
          open: true,
          pursuit_id: "story-composite",
          header: active_movie_header(),
          status: downloading_status(),
          unit_board: composite_unit_board(),
          timeline: short_timeline(),
          on_close: close_event(:open_composite_pursuit)
        }
      },
      %Variation{
        id: :open_not_found,
        description: "Open — pursuit id resolves to nothing (deleted or invalid deep link).",
        attributes: %{
          open: true,
          not_found?: true,
          on_close: close_event(:open_not_found)
        }
      }
    ]
  end

  # --- close handler ---------------------------------------------------------

  defp close_event(variation_id) do
    {:eval,
     ~s|Phoenix.LiveView.JS.push("psb-assign", value: %{variation_id: #{inspect(variation_id)}, open: false})|}
  end

  # --- header fixtures -------------------------------------------------------

  defp active_movie_header do
    %PursuitHeader{
      id: "story-active",
      title: "Public Domain Feature 1925",
      state: :active,
      recipe: %Recipe{type: :tmdb, title: "Public Domain Feature 1925", tmdb_type: :movie, year: 1925},
      criteria_summary: "max_quality: 2160p, min_quality: 1080p",
      backdrop_url:
        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='1280' height='720'><defs><linearGradient id='g' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='%23355070'/><stop offset='1' stop-color='%23172033'/></linearGradient></defs><rect width='1280' height='720' fill='url(%23g)'/><circle cx='980' cy='180' r='240' fill='%236d8cb0' opacity='0.35'/></svg>",
      logo_url:
        "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='400' height='90'><text x='0' y='64' font-family='sans-serif' font-size='56' font-weight='800' letter-spacing='6' fill='white'>SAMPLE FEATURE</text></svg>"
    }
  end

  defp awaiting_decision_header do
    %PursuitHeader{
      id: "story-decision",
      title: "Sample Show S01E04",
      state: :active,
      awaiting_decision?: true,
      recipe: %Recipe{
        type: :tmdb,
        title: "Sample Show",
        tmdb_type: :tv,
        season_number: 1,
        episode_number: 4
      },
      criteria_summary: nil
    }
  end

  defp satisfied_header do
    %PursuitHeader{
      id: "story-satisfied",
      title: "Movie A",
      state: :satisfied,
      recipe: %Recipe{type: :tmdb, title: "Movie A", tmdb_type: :movie, year: 2023},
      criteria_summary: nil
    }
  end

  # --- status fixtures -------------------------------------------------------

  defp downloading_status do
    %PursuitStatus{
      pursuit_id: "story-active",
      title: "Public Domain Feature 1925",
      state: :active,
      origin: :auto,
      recipe: %Recipe{type: :tmdb, title: "Public Domain Feature 1925", tmdb_type: :movie},
      current_action: %CurrentAction{
        verb: "Downloading",
        description: "From qBittorrent • 42% • ETA 8m",
        severity: :info
      },
      next_step: %NextStep{description: "When complete, the file watcher matches the title."},
      download: %DownloadProgress{
        state: :downloading,
        progress_pct: 42.0,
        client: "qBittorrent",
        eta: "8m"
      },
      available_actions: [:cancel],
      staleness: :fresh
    }
  end

  defp awaiting_decision_status do
    %PursuitStatus{
      pursuit_id: "story-decision",
      title: "Sample Show S01E04",
      state: :active,
      origin: :auto,
      recipe: %Recipe{type: :tmdb, title: "Sample Show", tmdb_type: :tv},
      current_action: %CurrentAction{
        verb: "Decision needed",
        description: "Pick a release below.",
        severity: :warning
      },
      next_step: %NextStep{description: "Use the decision card below to pick or skip."},
      available_actions: [:cancel],
      staleness: :fresh
    }
  end

  defp satisfied_status do
    %PursuitStatus{
      pursuit_id: "story-satisfied",
      title: "Movie A",
      state: :satisfied,
      origin: :auto,
      recipe: %Recipe{type: :tmdb, title: "Movie A", tmdb_type: :movie},
      current_action: %CurrentAction{
        verb: "Done",
        description: "File landed and identity verified.",
        severity: :success
      },
      next_step: nil,
      available_actions: [],
      staleness: :fresh
    }
  end

  # --- decision-card fixtures ------------------------------------------------

  defp many_alternatives do
    %DecisionCard{
      pursuit_id: "story-decision",
      prompt: "Download stalled for 24+ hours — pick an alternative release.",
      alternatives: [
        %Alternative{
          guid: "alt-uhd",
          title: "Sample.Show.S01E04.2160p.UHD.BluRay.REMUX-FGT",
          indexer: "ExampleIndexer",
          quality: "4K",
          size_bytes: 12_000_000_000,
          seeders: 8
        },
        %Alternative{
          guid: "alt-1080",
          title: "Sample.Show.S01E04.1080p.WEB-DL.H264-NTG",
          indexer: "ExampleIndexer",
          quality: "1080p",
          size_bytes: 2_500_000_000,
          seeders: 47
        },
        %Alternative{
          guid: "alt-720",
          title: "Sample.Show.S01E04.720p.WEB-DL.x264-AMIABLE",
          indexer: "AnotherIndexer",
          quality: "720p",
          size_bytes: 1_400_000_000,
          seeders: 33
        }
      ],
      loading?: false
    }
  end

  # --- timeline fixtures -----------------------------------------------------

  defp ago(seconds), do: DateTime.add(~U[2026-05-08 12:00:00Z], -seconds)

  defp entry(kind, summary, severity, occurred_at, detail \\ nil) do
    %TimelineEntry{
      kind: kind,
      occurred_at: occurred_at,
      summary: summary,
      severity: severity,
      detail: detail
    }
  end

  defp short_timeline do
    %Timeline{
      pursuit_id: "story-active",
      entries: [
        entry("download_started", "Download started", :info, ago(180)),
        entry(
          "release_picked",
          "Release picked — Public.Domain.Feature.1925.1080p",
          :success,
          ago(240),
          "ExampleIndexer • 1080p"
        ),
        entry("pursuit_started", "Pursuit started (auto)", :info, ago(300))
      ]
    }
  end

  defp stall_timeline do
    %Timeline{
      pursuit_id: "story-decision",
      entries: [
        entry("user_decision_requested", "User decision requested", :info, ago(600)),
        entry("stall_confirmed", "Stall confirmed", :warning, ago(86_400)),
        entry("download_started", "Download started", :info, ago(172_800)),
        entry("pursuit_started", "Pursuit started (auto)", :info, ago(259_200))
      ]
    }
  end

  defp stall_to_satisfied_timeline do
    %Timeline{
      pursuit_id: "story-satisfied",
      entries: [
        entry("pursuit_satisfied", "Pursuit satisfied", :success, ago(60)),
        entry(
          "identity_verified",
          "Identity verified",
          :success,
          ago(120),
          "/library/incoming/Movie.A.2023.1080p.mkv"
        ),
        entry("download_started", "Download started", :info, ago(180)),
        entry("pursuit_started", "Pursuit started (auto)", :info, ago(259_200))
      ]
    }
  end

  defp composite_unit_board do
    %MediaCentaur.Acquisition.ViewModels.UnitBoard{
      pursuit_id: "story-composite",
      wanted: 3,
      satisfied: 1,
      units: [
        %MediaCentaur.Acquisition.ViewModels.UnitBoard.Row{
          id: "story-unit-1",
          label: "Sample Show S01E01",
          state: :satisfied,
          release_title: "Sample.Show.S01E01.1080p.WEB-DL"
        },
        %MediaCentaur.Acquisition.ViewModels.UnitBoard.Row{
          id: "story-unit-2",
          label: "Sample Show S01E02",
          state: :active,
          release_title: "Sample.Show.S01E02.1080p.WEB-DL",
          actionable?: true
        },
        %MediaCentaur.Acquisition.ViewModels.UnitBoard.Row{
          id: "story-unit-3",
          label: "Sample Show S01E03",
          state: :active,
          awaiting_decision?: true
        }
      ]
    }
  end
end
