defmodule MediaCentaur.Showcase.ReviewScenarios do
  @moduledoc """
  Every way a file can sit in Review → Identity, reproduced on demand
  through the real pipeline.

  A scenario is an input — placeholder files on disk, the TMDB answers for
  their titles, and optionally a person's action — and a review state is
  its output. `seed!/1` lays the files into a showcase-mode instance's
  media directory, runs discovery over them (`Watcher.Rescan.scan/0`),
  waits until each lands in the queue for the reason its scenario names
  (`Review.reason/1`), takes the scenario's action through `Review`
  (match, dismiss) and waits again.

  The files are empty: discovery reads only their paths
  (`Watcher.VideoFile`). TMDB's answers for the placeholder titles are
  hand-written fixtures under `priv/showcase/tmdb/authored/`
  (`MediaCentaur.Showcase.Stubs.TmdbFixtures`). Titles are placeholders
  (CLAUDE.md § Test and example content).

  Not reproduced as a resting state, deliberately: *importing* lasts only
  from a match until the import finishes (press a match to see it); a
  *remembered match* would import placeholder titles into the library the
  marketing screenshots show (press a match to make one; Settings → Media
  Import lists it); a *rescan refresh* needs a parser change, not a file.

  `scenarios/0` is the catalog; `test/media_centaur/showcase/review_scenarios_test.exs`
  runs every file through discovery and checks it lands as listed.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Review
  alias MediaCentaur.Showcase.AcquisitionRows

  @type reason :: :no_results | :low_confidence | :tied | :not_added | :dismissed
  @type scenario :: %{
          name: String.t(),
          files: [Path.t()],
          lands_in: reason(),
          then: nil | :dismiss | {:match, map()},
          ends_in: reason()
        }

  @wait_ms 60_000
  @poll_ms 250

  # The grab the grab-conflict scenario's file came from: what acquisition
  # asked for, under the release name the file landed as.
  @grab %{
    release_title: "Movie.I.2003.1080p.BluRay.x264-GRP",
    tmdb_id: "990010",
    title: "Movie J",
    year: 2003
  }

  @doc "The scenario catalog."
  @spec scenarios() :: [scenario()]
  def scenarios do
    Enum.map(
      [
        %{
          name: "Release folders",
          files:
            for n <- 1..6 do
              release = "Sample.Show.S01E0#{n}.1080p.WEB-DL.x264-GRP"
              "#{release}/#{release}.mkv"
            end,
          lands_in: :no_results
        },
        %{
          name: "Remake year",
          files: ["Movie A (1968)/Movie A (1968).mkv", "Movie A/Movie A.mkv"],
          lands_in: :no_results
        },
        %{name: "Unsure", files: ["Movie B (2004)/Movie B (2004).mkv"], lands_in: :low_confidence},
        %{name: "Tied", files: ["Movie C/Movie C.mkv"], lands_in: :tied},
        %{
          name: "Not added",
          files: ["Movie.D.2001.1080p.BluRay.x264-GRP/Movie.D.2001.1080p.BluRay.x264-GRP.mkv"],
          lands_in: :low_confidence,
          then: {:match, %{tmdb_id: 990_004, tmdb_type: "movie", title: "Movie Dee", year: 1999}},
          ends_in: :not_added
        },
        %{
          name: "Dismissed",
          files: ["Movie E (1955)/Movie E (1955).mkv"],
          lands_in: :no_results,
          then: :dismiss,
          ends_in: :dismissed
        },
        %{name: "Generic name", files: ["Movie F (1999)/movie.mkv"], lands_in: :no_results},
        %{
          name: "Mixed folder",
          files: ["Sample Collection/Movie G (1950).mkv", "Sample Collection/Movie H (1960).mkv"],
          lands_in: :no_results
        },
        %{
          name: "Extras",
          files: [
            "Sample Show B/Season 01/Sample.Show.B.S01E01.mkv",
            "Sample Show B/Extras/Behind the Scenes.mkv"
          ],
          lands_in: :low_confidence
        },
        %{
          name: "Grab conflict",
          files: ["#{@grab.release_title}/#{@grab.release_title}.mkv"],
          lands_in: :low_confidence
        }
      ],
      &Map.merge(%{then: nil, ends_in: &1.lands_in}, &1)
    )

    # Six episodes, each in its own release folder; the pipeline's search
    # finds nothing, the search bar finds the show (`Sample Show`, 990001),
    # and pressing it matches all six.
    # The same name with and without a year: two dividers.
    # The best guess is a different title from another year.
    # Two titles share the name and no year breaks the tie.
    # Matched to a title whose import fails: back in review with the reason.
    # A generic file name; the folder carries the title.
    # One folder holding two different titles.
    # A show with a bonus-features folder; both wait on the show's match.
    # A grab asked for one title; the search confidently finds another
    # under the release name (`Pipeline.Stages.Search`, `GrabProvenance`).
  end

  @doc """
  The rows the scenarios need before their files land: the acquisition
  grab behind the grab-conflict scenario.
  """
  @spec prepare!() :: :ok
  def prepare! do
    AcquisitionRows.insert!(
      pursuit_attrs: %{
        recipe_type: "tmdb",
        tmdb_id: @grab.tmdb_id,
        tmdb_type: "movie",
        title: @grab.title,
        year: @grab.year,
        origin: "manual",
        state: "done"
      },
      target_attrs: %{
        title: @grab.release_title,
        release_title: @grab.release_title,
        status: "acquired",
        origin: "manual"
      }
    )

    :ok
  end

  @doc """
  Lays every scenario down in `media_dir` and drives it to its resting
  state. Raises naming the files that did not arrive in time. Returns how
  many files it laid down.
  """
  @spec seed!(Path.t()) :: non_neg_integer()
  def seed!(media_dir) do
    prepare!()

    files =
      for scenario <- scenarios(), file <- scenario.files, do: {Path.join(media_dir, file), scenario}

    for {path, _scenario} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "")
    end

    {:ok, _count} = MediaCentaur.Watcher.Rescan.scan()
    await!(files, & &1.lands_in)

    for {scenario, paths} <- Enum.group_by(files, &elem(&1, 1), &elem(&1, 0)), scenario.then do
      act!(scenario.then, ids_for(paths))
    end

    await!(files, & &1.ends_in)

    Log.info(
      :system,
      "showcase review scenarios: #{length(files)} files in #{length(scenarios())} scenarios"
    )

    length(files)
  end

  defp act!(:dismiss, ids), do: {:ok, _} = Review.dismiss(ids)
  defp act!({:match, title}, ids), do: {:ok, _} = Review.match(ids, title)

  defp ids_for(paths) do
    for file <- Review.list_queue(), file.file_path in paths, do: file.id
  end

  defp await!(files, state_of) do
    deadline = System.monotonic_time(:millisecond) + @wait_ms
    wait_until(files, state_of, deadline)
  end

  defp wait_until(files, state_of, deadline) do
    by_path = Map.new(Review.list_queue(), &{&1.file_path, state(&1)})

    waiting =
      for {path, scenario} <- files, by_path[path] != state_of.(scenario), do: {path, by_path[path]}

    cond do
      waiting == [] ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        raise "review scenarios did not settle: " <>
                Enum.map_join(waiting, "; ", fn {path, found} -> "#{path} is #{inspect(found)}" end)

      true ->
        Process.sleep(@poll_ms)
        wait_until(files, state_of, deadline)
    end
  end

  defp state(%{status: :dismissed}), do: :dismissed
  defp state(file), do: Review.reason(file)
end
