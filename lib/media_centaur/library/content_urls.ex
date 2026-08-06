defmodule MediaCentaur.Library.ContentUrls do
  @moduledoc """
  Materialises the virtual `:content_url` field on fetched records from
  the WatchedFile chain.

  The leaf types `Movie`, `Episode`, and `VideoObject` carry
  `content_url` as a *virtual* schema field — Library Schema v2 Phase 2
  Task I dropped the persisted column, so the on-disk path now lives
  only on `library_watched_files.file_path`, reachable via
  `PlayableItem`. This module is the single read-time seam that stamps
  the virtual back onto the struct, so downstream consumers
  (`EntityShape`, `EpisodeList`, `MovieList`, the detail panel) keep
  their natural `record.content_url` reads.

  `populate/1` walks the record's preloaded `playable_items.watched_files`
  and records the first WatchedFile's `file_path` on the leaf, stamping
  `nil` when no WatchedFile is linked — the same shape the dropped
  column carried. Containers recurse: `:seasons → :episodes` for
  `TVSeries`, `:movies` for `MovieSeries`.

  Callers must preload `playable_items: :watched_files` at the leaf
  level. `Library.Containers.full_preloads_by_type/0` and every
  `Containers.fetch*` path already include it.
  """

  alias MediaCentaur.Library.{
    Episode,
    Movie,
    MovieSeries,
    PlayableItem,
    Season,
    TVSeries,
    VideoObject,
    WatchedFile
  }

  @leaf_preload [playable_items: :watched_files]

  @doc """
  The preload chain `populate/1` needs at the leaf level.

  Owned here rather than by each caller so the stamping rule and the
  preload it depends on can never drift apart.
  """
  @spec required_preload() :: keyword()
  def required_preload, do: @leaf_preload

  @doc """
  Stamps `:content_url` on a record and any preloaded leaves beneath it.

  Returns the record unchanged when it carries no `content_url` surface,
  and `nil` for `nil` so it composes in a fetch pipeline.
  """
  @spec populate(struct() | nil) :: struct() | nil
  def populate(nil), do: nil

  def populate(%Movie{} = movie), do: populate_leaf(movie)

  def populate(%Episode{} = episode), do: populate_leaf(episode)

  def populate(%VideoObject{} = video), do: populate_leaf(video)

  def populate(%TVSeries{seasons: seasons} = tv_series) when is_list(seasons) do
    %{tv_series | seasons: Enum.map(seasons, &populate_season/1)}
  end

  def populate(%MovieSeries{movies: movies} = movie_series) when is_list(movies) do
    %{movie_series | movies: Enum.map(movies, &populate_leaf/1)}
  end

  def populate(other), do: other

  defp populate_season(%Season{episodes: episodes} = season) when is_list(episodes) do
    %{season | episodes: Enum.map(episodes, &populate_leaf/1)}
  end

  defp populate_season(season), do: season

  defp populate_leaf(%{playable_items: playable_items} = leaf) when is_list(playable_items) do
    url =
      playable_items
      # Multi-PlayableItem leaves (multi-cut Movie, multi-part Episode)
      # pick the lowest `:position` PI for the content_url surface — a
      # deterministic canonical-cut choice rather than whatever order
      # Repo happened to return. Per Phase 2 follow-up.
      |> Enum.sort_by(& &1.position)
      |> Enum.find_value(fn
        %PlayableItem{watched_files: [%WatchedFile{file_path: path} | _]} when is_binary(path) ->
          path

        _ ->
          nil
      end)

    %{leaf | content_url: url}
  end

  defp populate_leaf(%{playable_items: %Ecto.Association.NotLoaded{}} = leaf) do
    # Loud failure replaces a Phase 2 silent-nil: callers must preload
    # `playable_items: :watched_files`. The pre-Phase-3.2 silent path
    # masked missing-preload bugs (leaf rendered with `content_url:
    # nil`) until the consumer dereferenced the missing field at render
    # time. Raising here surfaces the bug at the test boundary instead.
    raise ArgumentError,
          "ContentUrls.populate/1 called on #{inspect(leaf.__struct__)} without :playable_items preloaded. " <>
            "Preload `playable_items: :watched_files` before calling this function."
  end

  defp populate_leaf(leaf), do: leaf
end
