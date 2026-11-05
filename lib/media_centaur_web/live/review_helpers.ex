defmodule MediaCentaurWeb.ReviewHelpers do
  @moduledoc """
  Pure helper functions for the review LiveView (ADR-030) — reason
  classification, labels, and the bulk list: statuses, the
  filter, the rows with their dividers, ticks, the search prefill and the
  delete partitions.

  The bulk list has no groups (campaign `review-bulk-match`). Rows follow
  `Review.list_queue/0`'s order, and a divider marks where the parsed
  title or year changes; ticking it ticks the rows beneath it, and it
  decides nothing. What a person ticks is what an action applies to.
  """

  alias MediaCentaur.Search.TitleForm

  # --- Reason Display ---

  def reason_label(:no_results), do: "No TMDB results"
  def reason_label(:low_confidence), do: "Low confidence"
  def reason_label(:tied), do: "Tied match"
  def reason_label(:importing), do: "Importing"
  def reason_label(:not_added), do: "Not added"

  def reason_text_class(:no_results), do: "text-error"
  def reason_text_class(:low_confidence), do: "text-warning"
  def reason_text_class(:tied), do: "text-info"
  def reason_text_class(:importing), do: "text-base-content/60"
  def reason_text_class(:not_added), do: "text-error"

  # --- Type Formatting ---

  def format_type("movie"), do: "Movie"
  def format_type("tv"), do: "TV"
  def format_type("extra"), do: "Extra"
  def format_type("unknown"), do: "Unknown"
  def format_type(nil), do: "Unknown"
  def format_type(type) when is_atom(type), do: type |> Atom.to_string() |> String.capitalize()
  def format_type(type), do: type |> to_string() |> String.capitalize()

  # --- Bulk list ---

  @typedoc "Which items the list shows: one status at a time."
  @type status :: :waiting | :importing | :dismissed

  @doc "The list status of a review item: waiting on a person, importing, or dismissed."
  @spec status_of(map()) :: status()
  def status_of(%{status: :approved}), do: :importing
  def status_of(%{status: :dismissed}), do: :dismissed
  def status_of(_waiting), do: :waiting

  @doc "How many items each status holds."
  @spec count_by_status([map()]) :: %{status() => non_neg_integer()}
  def count_by_status(files) do
    Enum.reduce(files, %{waiting: 0, importing: 0, dismissed: 0}, fn file, acc ->
      Map.update!(acc, status_of(file), &(&1 + 1))
    end)
  end

  @doc """
  The items of `status` that the filter `query` matches: the query, in
  folded form, inside the parsed title or the file name. Separators do not
  count, so `sample show` finds `Sample.Show.2005.S01E07.mkv`.
  """
  @spec visible([map()], status(), String.t()) :: [map()]
  def visible(files, status, query) do
    needle = TitleForm.compare(query || "")

    Enum.filter(files, fn file ->
      status_of(file) == status and
        (needle == "" or
           String.contains?(TitleForm.compare(file.parsed_title || ""), needle) or
           String.contains?(TitleForm.compare(Path.basename(file.file_path)), needle))
    end)
  end

  @doc """
  The list's rows, in `files`' order: `{:divider, %{id, label, ids}}`
  wherever the parsed title (case-folded) or year changes, then
  `{:item, file}` for each item beneath it.
  """
  @spec rows([map()]) :: [{:divider, map()} | {:item, map()}]
  def rows(files) do
    files
    |> Enum.chunk_by(&{String.downcase(&1.parsed_title || ""), &1.parsed_year})
    |> Enum.flat_map(fn [first | _] = block ->
      ids = Enum.map(block, & &1.id)

      label =
        if first.parsed_year,
          do: "#{first.parsed_title} (#{first.parsed_year})",
          else: first.parsed_title || "Unknown"

      [{:divider, %{id: "divider-" <> first.id, label: label, ids: ids}} | Enum.map(block, &{:item, &1})]
    end)
  end

  @doc "Ticks `ids` when any of them is unticked; unticks them all when every one is ticked."
  @spec toggle(MapSet.t(), [String.t()]) :: MapSet.t()
  def toggle(selected, ids) do
    if Enum.all?(ids, &MapSet.member?(selected, &1)),
      do: MapSet.difference(selected, MapSet.new(ids)),
      else: MapSet.union(selected, MapSet.new(ids))
  end

  @doc "A block's checkbox: `:checked`, `:indeterminate` when some are ticked, else `:unchecked`."
  @spec tick_state(MapSet.t(), [String.t()]) :: :checked | :indeterminate | :unchecked
  def tick_state(_selected, []), do: :unchecked

  def tick_state(selected, ids) do
    case Enum.count(ids, &MapSet.member?(selected, &1)) do
      0 -> :unchecked
      count when count == length(ids) -> :checked
      _some -> :indeterminate
    end
  end

  @doc """
  What the action bar's search starts from: the first ticked item's parsed
  title, searched as its type — an extra with a season as a series, one
  without as a film. `nil` with nothing ticked.
  """
  @spec search_prefill([map()], MapSet.t()) :: {String.t(), :tv | :movie} | nil
  def search_prefill(files, selected) do
    case Enum.find(files, &MapSet.member?(selected, &1.id)) do
      nil -> nil
      file -> {file.parsed_title || "", search_type(file)}
    end
  end

  defp search_type(%{parsed_type: "tv"}), do: :tv
  defp search_type(%{parsed_type: "extra", parsed_season: season}) when is_integer(season), do: :tv
  defp search_type(_file), do: :movie

  @doc "Whether the ticked items can be accepted under their own best guesses: every one has one."
  @spec accept_guesses?([map()]) :: boolean()
  def accept_guesses?([]), do: false
  def accept_guesses?(files), do: Enum.all?(files, &(&1.tmdb_id != nil))

  @doc """
  `paths` split by the folder that holds them, in first-seen order. Each
  part is judged on its own by `MediaCentaur.DeleteTargets`, so a
  selection spanning release folders deletes those folders, never a
  common ancestor.
  """
  @spec delete_partitions([String.t()]) :: [[String.t()]]
  def delete_partitions(paths) do
    paths
    |> Enum.group_by(&Path.dirname/1)
    |> Enum.sort_by(fn {_dir, [first | _]} -> Enum.find_index(paths, &(&1 == first)) end)
    |> Enum.map(fn {_dir, part} -> part end)
  end

  @doc "`S01E07` for an item with a parsed season and episode, else an empty string."
  @spec episode_label(map()) :: String.t()
  def episode_label(%{parsed_season: season, parsed_episode: episode})
      when is_integer(season) and is_integer(episode), do: "S#{pad(season)}E#{pad(episode)}"

  def episode_label(_file), do: ""

  defp pad(number), do: number |> to_string() |> String.pad_leading(2, "0")

  @doc """
  The armed Delete's words for a resolved delete plan — each part a
  `{:folder, dir, paths}` that goes whole (`DeleteTargets` found it safe)
  or `{:files, paths}` deleted one by one.
  """
  @spec delete_label([{:folder, String.t(), [String.t()]} | {:files, [String.t()]}]) :: String.t()
  def delete_label(plan) do
    files = Enum.sum(for part <- plan, do: length(elem(part, tuple_size(part) - 1)))
    folders = Enum.count(plan, &match?({:folder, _dir, _paths}, &1))

    "Press again to delete " <>
      plural(files, "file") <> if(folders > 0, do: " and " <> plural(folders, "folder"), else: "")
  end

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(count, noun), do: "#{count} #{noun}s"
end
