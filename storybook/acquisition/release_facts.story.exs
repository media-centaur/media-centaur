defmodule MediaCentaurWeb.Storybook.Acquisition.ReleaseFacts do
  @moduledoc """
  The one vocabulary for a release candidate's facts — quality label
  (tier-colored), monospace filename title, decimal size, health-colored
  seeders — shared by the plan board, the pickers, the decision card,
  and the release-search zone.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaurWeb.Components.Acquisition.ReleaseFacts.Entry

  def function, do: &MediaCentaurWeb.Components.Acquisition.ReleaseFacts.release_facts/1
  def render_source, do: :function

  # The component renders a fragment of flex children — stand in the
  # glass row every caller provides.
  def template do
    """
    <div class="glass-inset rounded-lg px-3 py-2 flex items-center gap-3">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :full_row,
        description:
          "Everything at once — scope badge, tier-colored quality, source label (parsed " <>
            "from the title, ADR-061), filename title, decimal size, healthy seeders, indexer.",
        attributes: %{
          entry: %Entry{
            title: "Sample.Show.S01.COMPLETE.1080p.WEB-DL.x264-GROUP",
            scope_label: "Season 1 pack",
            quality: "1080p",
            size_bytes: 9_400_000_000,
            seeders: 34,
            indexer: "indexer-a"
          }
        }
      },
      %Variation{
        id: :four_k_healthy,
        description: "4K reads healthy-green; seeders ≥10 are green too.",
        attributes: %{
          entry: %Entry{
            title: "Sample.Movie.2005.2160p.WEB-DL.x265-GROUP",
            quality: "4K",
            size_bytes: 28_000_000_000,
            seeders: 12
          }
        }
      },
      %Variation{
        id: :search_ladder_atom,
        description:
          "The release-search zone hands the quality ladder's atom instead of a label " <>
            "string — same colors, same words.",
        attributes: %{
          entry: %Entry{
            title: "Sample.Show.S01E01.1080p.WEB-DL.x264",
            quality: :hd_1080p,
            size_bytes: 2_100_000_000,
            seeders: 5,
            indexer: "indexer-b"
          }
        }
      },
      %Variation{
        id: :unknown_quality_thin_seeders,
        description:
          "No quality in the release name → an honest muted \"Unknown\"; 3–9 seeders read " <>
            "thin (amber).",
        attributes: %{
          entry: %Entry{
            title: "Sample.Movie.2005.AMZN.WEB-DL.DDP2.0.H.264",
            quality: nil,
            size_bytes: 1_000_000_000,
            seeders: 4
          }
        }
      },
      %Variation{
        id: :remux_source,
        description:
          "A remux title carries the \"Remux\" source label — the ladder's top pick under " <>
            "the fidelity preference.",
        attributes: %{
          entry: %Entry{
            title: "Sample.Movie.1998.BluRay.1080p.REMUX.VC-1.DTS-HD.MA.5.1-GROUP",
            quality: "1080p",
            size_bytes: 28_400_000_000,
            seeders: 11
          }
        }
      },
      %Variation{
        id: :no_source_signal,
        description: "No source token in the title → no source label, nothing fabricated.",
        attributes: %{
          entry: %Entry{
            title: "Sample.Movie.1998.1080p.x264-GROUP",
            quality: "1080p",
            size_bytes: 4_100_000_000,
            seeders: 7
          }
        }
      },
      %Variation{
        id: :suspicious_dying,
        description:
          "Executable-bait pattern flagged \"looks fake\" but still choosable; <3 seeders " <>
            "read dying (red).",
        attributes: %{
          entry: %Entry{
            title: "Sample.Show.S01E01.1080p.HD.X264.1080p.exe",
            quality: "1080p",
            size_bytes: 4_000_000,
            seeders: 1,
            suspicious?: true
          }
        }
      }
    ]
  end
end
