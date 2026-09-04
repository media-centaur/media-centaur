defmodule MediaCentaurWeb.Storybook.Detail.ManagePanel do
  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Library.EntityView
  alias MediaCentaur.Library.ExternalId
  alias MediaCentaur.Library.WatchedFile

  def function, do: &MediaCentaurWeb.Components.Detail.ManagePanel.manage_panel/1
  def render_source, do: :function
  def layout, do: :one_column

  # The sheet renders inside the modal's scrolling body — constrain to
  # the panel's width so row truncation and the toolbar card's wrap
  # behave as they do in production.
  def template do
    """
    <div class="max-w-[760px]">
      <.psb-variation/>
    </div>
    """
  end

  @entity %EntityView{
    id: "00000000-0000-0000-0000-00000000c0a1",
    type: :tv_series,
    name: "Sample Show",
    url: "https://www.themoviedb.org/tv/4556",
    external_ids: [
      %ExternalId{source: "tmdb", external_id: "4556"},
      %ExternalId{source: "imdb", external_id: "tt0000001"},
      %ExternalId{source: "tvdb", external_id: "76156"}
    ]
  }

  # Eight files across two season folders — above the ≤6 auto-expand
  # threshold, so the ledger rests collapsed.
  defp season_files do
    for season <- 1..2, episode <- 1..4 do
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-fffffffff#{season}0#{episode}",
          file_path:
            "/media/tv/Sample Show/Season #{season}/Sample.Show.S0#{season}E0#{episode}.1080p.WEB-DL.mkv",
          media_dir: "/media/tv"
        },
        size: 183_500_800
      }
    end
  end

  # A movie-sized inventory (3 files, one absent) — at or below the
  # threshold, so every group opens without a toggle.
  defp movie_files do
    [
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff01",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.2160p.HDR.x265.mkv",
          media_dir: "/media/movies"
        },
        size: 4_294_967_296
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff02",
          file_path: "/media/movies/Sample Movie (1922)/Sample.Movie.1922.1080p.WEB-DL.mkv",
          media_dir: "/media/movies"
        },
        size: 1_073_741_824
      },
      %{
        file: %WatchedFile{
          id: "ffffffff-ffff-ffff-ffff-ffffffffff03",
          file_path: "/media/archive/Sample.Movie.1922.480p.legacy.mkv",
          media_dir: "/media/archive"
        },
        # `nil` size renders the "absent" badge — the file went missing
        # off disk after being indexed.
        size: nil
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :collapsed_ledger,
        description:
          "The resting state for a large inventory (8 files, above the ≤6 " <>
            "auto-expand threshold): toolbar card with **Delete all files " <>
            "(size)**, Rematch, Refresh artwork, and the external-ids + UUID " <>
            "edge; below it, one collapsed summary row per folder — name, " <>
            "count, size, quiet Delete. Zero file rows at rest.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: true
        }
      },
      %Variation{
        id: :group_expanded,
        description:
          "`expanded_groups: MapSet.new([dir])` — Season 1 open (chevron " <>
            "down, `aria-expanded=\"true\"`), its file rows sorted by " <>
            "filename with quality badges and per-file deletes; Season 2 " <>
            "stays a summary row.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: true,
          expanded_groups: {:eval, ~s|MapSet.new(["/media/tv/Sample Show/Season 1"])|}
        }
      },
      %Variation{
        id: :small_inventory_auto_expanded,
        description:
          "A movie-sized inventory (3 files, ≤ threshold) auto-expands — " <>
            "`expanded_groups: nil` computes the default, so a single file " <>
            "is never hidden behind a chevron. Includes an absent file " <>
            "(nil size → warning triangle + `absent`).",
        attributes: %{
          entity: %{@entity | type: :movie, name: "Sample Movie"},
          files: movie_files(),
          tmdb_ready: true
        }
      },
      %Variation{
        id: :delete_pending_all,
        description:
          "`delete_confirm: :all` — the toolbar's danger button reads " <>
            "**Click again to confirm — Delete all files (size)** with an " <>
            "inline **Cancel** beside it. No secondary modal.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: true,
          delete_confirm: :all
        }
      },
      %Variation{
        id: :delete_pending_folder,
        description:
          "`delete_confirm: {:folder, dir}` — the collapsed row's quiet " <>
            "Delete flips to **Click again to confirm** without the group " <>
            "having to open.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: true,
          delete_confirm: {:eval, ~s|{:folder, "/media/tv/Sample Show/Season 1"}|}
        }
      },
      %Variation{
        id: :delete_pending_file,
        description:
          "`delete_confirm: {:file, path}` targeting a row inside an " <>
            "expanded group — danger tint, error ring, trash button widens " <>
            "to **Click to confirm**.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: true,
          expanded_groups: {:eval, ~s|MapSet.new(["/media/tv/Sample Show/Season 1"])|},
          delete_confirm:
            {:eval, ~s|{:file, "/media/tv/Sample Show/Season 1/Sample.Show.S01E01.1080p.WEB-DL.mkv"}|}
        }
      },
      %Variation{
        id: :deleting_in_flight,
        description:
          "`deleting: :all` — the async delete is running: the danger " <>
            "button reads **Deleting…** and every delete affordance on the " <>
            "sheet disables so destructive ops can't stack.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: true,
          deleting: :all
        }
      },
      %Variation{
        id: :tmdb_not_ready,
        description:
          "`tmdb_ready: false` — Rematch and Refresh artwork are replaced " <>
            "by the Settings hint inside the toolbar card; file cleanup is " <>
            "unaffected.",
        attributes: %{
          entity: @entity,
          files: season_files(),
          tmdb_ready: false
        }
      },
      %Variation{
        id: :no_files,
        description:
          "No files on disk — the ledger and Delete all are absent, but " <>
            "the toolbar card still carries the metadata tools and the " <>
            "identity edge. Manage is never a dead end.",
        attributes: %{
          entity: @entity,
          files: [],
          tmdb_ready: true
        }
      }
    ]
  end
end
