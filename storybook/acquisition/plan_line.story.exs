defmodule MediaCentaurWeb.Storybook.Acquisition.PlanLine do
  @moduledoc """
  One line of the plan board's manifest (UIDR-029 as amended 2026-11-06):
  a release with the episode cells it covers, or a group of cells
  sharing one outcome with that outcome's decision at the line's end.
  The lines come from the real projection, `Plans.Board.assemble/2`,
  over plan units, so a story can never show a line the app would not
  build. Cells speak the shared vocabulary (`CellVocabulary`): assigned
  cells in a release line fuse into its capsule; a lower-quality cell is
  the info outline, a not-found cell the amber outline, a dropped cell
  struck through, a searching cell dashed.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Plans.{Board, Plan, PlanUnit}

  def function, do: &MediaCentaurWeb.Components.Acquisition.PlanLine.plan_line/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :release_pack,
        description:
          "A season pack covering three episodes: the release's facts, Options and ✕ on a " <>
            "ready board, the cells fused into one capsule beneath.",
        attributes: %{line: line(:release_pack), ready?: true, movie?: false}
      },
      %Variation{
        id: :release_single,
        description: "A single covering one episode — one claimed cell, no capsule.",
        attributes: %{line: line(:release_single), ready?: true, movie?: false}
      },
      %Variation{
        id: :release_picker_open,
        description: "The same pack with its picker open beneath it: Options reads Hide.",
        attributes: %{line: line(:release_pack), ready?: true, movie?: false, picker_open: true}
      },
      %Variation{
        id: :release_with_overlap,
        description:
          "A pack that physically contains an episode now assigned to its own single (a " <>
            "swap-picker choice): the duplicate-data warning and Remove it & re-solve sit " <>
            "under the facts, on the line it concerns.",
        attributes: %{line: line(:release_with_overlap), ready?: true, movie?: false}
      },
      %Variation{
        id: :release_long_season,
        description: "A 26-episode season pack — the capsule wraps inside the line.",
        attributes: %{line: line(:release_long_season), ready?: true, movie?: false}
      },
      %Variation{
        id: :release_planning,
        description: "While planning: the facts and the capsule, no controls yet.",
        attributes: %{line: line(:release_pack), ready?: false, movie?: false}
      },
      %Variation{
        id: :release_movie,
        description: "A movie's release line: the facts alone — a movie shows no cells.",
        attributes: %{line: line(:release_movie), ready?: true, movie?: true}
      },
      %Variation{
        id: :searching,
        description: "The searching line: the episodes the run is still looking for, dashed.",
        attributes: %{line: line(:searching), ready?: false, movie?: false}
      },
      %Variation{
        id: :lower_quality,
        description:
          "Seven episodes available only in lower quality: the grouped sentence, the " <>
            "info edge, Show them (one unit only) and Take lower quality for this show.",
        attributes: %{line: line(:lower_quality), ready?: true, movie?: false}
      },
      %Variation{
        id: :lower_quality_one,
        description: "One episode below preference — Show them opens its picker directly.",
        attributes: %{line: line(:lower_quality_one), ready?: true, movie?: false}
      },
      %Variation{
        id: :not_found,
        description:
          "Not found across two seasons: one line, a row per season, the amber edge, " <>
            "Search again.",
        attributes: %{line: line(:not_found), ready?: true, movie?: false}
      },
      %Variation{
        id: :not_found_movie_rejected,
        description:
          "A movie whose results all failed a gate (the rejected world, UIDR-022): " <>
            "Show them anyway beside Search again; no cells.",
        attributes: %{line: line(:not_found_movie), ready?: true, movie?: true, rejectable?: true}
      },
      %Variation{
        id: :offer,
        description:
          "A fit-gated pack offer: the only thing covering the episode is a season pack; " <>
            "Grab the pack is the explicit over-grab.",
        attributes: %{line: line(:offer), ready?: true, movie?: false}
      },
      %Variation{
        id: :dropped,
        description: "Episodes the user dropped: struck through, no edge — press one to put it back.",
        attributes: %{line: line(:dropped), ready?: true, movie?: false}
      }
    ]
  end

  # --- fixtures, through the real projection ---------------------------------

  defp line(:release_pack),
    do: only(:release, [found(1, 1, "pack"), found(1, 2, "pack"), found(1, 3, "pack")])

  defp line(:release_single), do: only(:release, [found(2, 1, "single")])

  defp line(:release_with_overlap) do
    only(:release, [found(1, 1, "pack"), found(1, 2, "single-s1e2"), found(1, 3, "pack")], "pack")
  end

  defp line(:release_long_season), do: only(:release, Enum.map(1..26, &found(2, &1, "pack")))

  defp line(:release_movie) do
    only(
      :release,
      [
        movie_unit(
          status: "found",
          assigned_guid: "movie",
          assigned_title: "Sample.Movie.2010.1080p.WEB-DL.x264-GRP",
          assigned_scope: "Movie",
          assigned_quality: "1080p",
          assigned_seeders: 41,
          assigned_size_bytes: 4_200_000_000
        )
      ],
      nil,
      "movie"
    )
  end

  defp line(:searching),
    do: only(:searching, [unit(1, 3), unit(1, 4), unit(2, 1)], nil, "tv", "planning")

  defp line(:lower_quality) do
    only(
      :below_preference,
      Enum.map([1, 2, 3, 5, 6, 7, 8], &unit(1, &1, status: "unfound", below_floor_count: 4 + rem(&1, 2)))
    )
  end

  defp line(:lower_quality_one),
    do: only(:below_preference, [unit(1, 5, status: "unfound", below_floor_count: 3)])

  defp line(:not_found),
    do: only(:not_found, [unit(1, 3, status: "unfound"), unit(2, 1, status: "unfound")])

  defp line(:not_found_movie), do: only(:not_found, [movie_unit(status: "unfound")], nil, "movie")

  defp line(:offer) do
    only(:offer, [
      unit(1, 3,
        status: "unfound",
        offered_guid: "s1-pack",
        offered_title: "Sample.Show.S01.COMPLETE.1080p.WEB-DL",
        offered_scope: "Season 1 pack",
        offered_size_bytes: 9_400_000_000
      )
    ])
  end

  defp line(:dropped),
    do: only(:excluded, [unit(1, 4, status: "excluded"), unit(1, 5, status: "excluded")])

  # The one line of the given kind a board over these units builds; `guid`
  # picks among several release lines.
  defp only(kind, units, guid \\ nil, tmdb_type \\ "tv", status \\ "ready") do
    plan = %Plan{
      id: "story-plan",
      title: "Sample Show",
      status: status,
      tmdb_type: tmdb_type,
      criteria: %{}
    }

    plan
    |> Board.assemble(units)
    |> Map.fetch!(:lines)
    |> Enum.find(fn line -> line.kind == kind and (is_nil(guid) or line.release.guid == guid) end)
  end

  defp unit(season, episode, attrs \\ []) do
    struct!(
      %PlanUnit{
        id: "story-unit-#{season}-#{episode}",
        plan_id: "story-plan",
        season_number: season,
        episode_number: episode,
        label: "S0#{season}E#{String.pad_leading(to_string(episode), 2, "0")} · Episode #{episode}",
        position: season * 100 + episode,
        status: "pending"
      },
      attrs
    )
  end

  defp movie_unit(attrs) do
    struct!(
      %PlanUnit{
        id: "story-unit-movie",
        plan_id: "story-plan",
        label: "Sample Movie",
        position: 0,
        status: "pending"
      },
      attrs
    )
  end

  defp found(season, episode, guid) do
    unit(season, episode,
      status: "found",
      assigned_guid: guid,
      assigned_title: release_title(guid, season, episode),
      assigned_scope: release_scope(guid, season, episode),
      assigned_quality: if(guid == "single-s1e2", do: "2160p", else: "1080p"),
      assigned_seeders: 34,
      assigned_size_bytes: 3_100_000_000
    )
  end

  defp release_title("pack", season, _episode), do: "Sample.Show.S0#{season}.1080p.WEB-DL.x264-GRP"
  defp release_title("single-s1e2", _season, _episode), do: "Sample.Show.S01E02.2160p.WEB-DL.x265-GRP"

  defp release_title(_single, season, episode),
    do: "Sample.Show.S0#{season}E#{String.pad_leading(to_string(episode), 2, "0")}.1080p.WEB-DL.x264-GRP"

  defp release_scope("pack", season, _episode), do: "Season #{season} pack"

  defp release_scope(_single, season, episode),
    do: "S0#{season}E#{String.pad_leading(to_string(episode), 2, "0")}"
end
