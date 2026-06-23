defmodule MediaCentaurWeb.ReconcileView do
  @moduledoc """
  Pure view logic for the episode-mapping review surface ([ADR-030]) — the
  LiveView stays thin wiring and these functions are unit-tested without a
  socket. Operates on `Reconciliation` read structs (`ShowReview`,
  `Resolution`, `SpineNode`, `AwaitingFile`).

  The `<select>` value encoding is `"season-episode"` (e.g. `"1-29"`), with
  the sentinel `"skip"` meaning "leave this file unmapped". `included_targets/1`
  turns the select state back into the `%{id => {season, episode}}` map
  `Reconciliation.confirm/2` expects, dropping skips (that *is* partial-accept).
  """

  alias MediaCentaur.Reconciliation.{Resolution, ShowReview, SpineNode}

  @skip "skip"

  @doc "The skip sentinel — leave a file unmapped."
  def skip, do: @skip

  def encode_node(%{season: season, episode: episode}), do: "#{season}-#{episode}"
  def encode_node({season, episode}), do: "#{season}-#{episode}"

  def decode_node(@skip), do: :skip

  def decode_node(value) when is_binary(value) do
    [season, episode] = String.split(value, "-")
    {String.to_integer(season), String.to_integer(episode)}
  end

  @doc "Seeds the per-file select values from the engine's recommendation."
  def initial_targets(%Resolution{recommended: nil}), do: %{}

  def initial_targets(%Resolution{recommended: %{placements: placements}}) do
    Map.new(placements, &{&1.artifact_id, encode_node(&1)})
  end

  @doc "Per-file select values from an interpretation's placements (adopting an alternative)."
  def targets_from_placements(placements) do
    Map.new(placements, &{&1.artifact_id, encode_node(&1)})
  end

  @doc "The `<select>` options: the skip sentinel, then every spine node, sorted."
  def episode_options(spine) do
    sorted = Enum.sort_by(spine, &{&1.season, &1.episode})
    [{"— don't map yet —", @skip} | Enum.map(sorted, &{option_label(&1), encode_node(&1)})]
  end

  def option_label(%SpineNode{} = node) do
    base = "S#{node.season} · E#{node.episode}"
    if node.title in [nil, ""], do: base, else: base <> " — " <> node.title
  end

  def target_value(targets, artifact_id), do: Map.get(targets, artifact_id, @skip)

  @doc "Turns the select state into confirm/2's target map, dropping skipped files."
  def included_targets(targets) do
    targets
    |> Enum.reject(fn {_id, value} -> value == @skip end)
    |> Map.new(fn {id, value} -> {id, decode_node(value)} end)
  end

  def confidence_pct(nil), do: nil
  def confidence_pct(confidence) when is_float(confidence), do: "#{round(confidence * 100)}%"

  def humanize_model(:gap_fill), do: "Fills the gap, in order"
  def humanize_model(:title_match), do: "Episode titles"
  def humanize_model(:recommended), do: "Recommended"
  def humanize_model(other), do: other |> to_string() |> String.replace("_", " ")

  @doc "One row per awaiting file: its path, claimed numbering, and current target."
  def file_rows(%ShowReview{} = review, targets) do
    title_by_node = Map.new(review.spine, &{{&1.season, &1.episode}, &1.title})

    Enum.map(review.awaiting_files, fn file ->
      value = target_value(targets, file.id)

      %{
        id: file.id,
        file_path: file.file_path,
        claimed: claimed_label(file),
        target_value: value,
        target_label: target_label(value, title_by_node)
      }
    end)
  end

  defp claimed_label(%{claimed_season: nil, claimed_episode: nil}), do: "—"
  defp claimed_label(%{claimed_season: season, claimed_episode: episode}), do: "S#{season} · E#{episode}"

  defp target_label(@skip, _title_by_node), do: nil

  defp target_label(value, title_by_node) do
    {season, episode} = decode_node(value)
    option_label(%SpineNode{season: season, episode: episode, title: title_by_node[{season, episode}]})
  end

  @doc "Master-list summaries: one entry per show with pending files, sorted by title."
  def show_summaries(awaiting_files) do
    awaiting_files
    |> Enum.group_by(& &1.tmdb_id)
    |> Enum.map(fn {tmdb_id, files} ->
      %{tmdb_id: tmdb_id, title: show_title(files), count: length(files)}
    end)
    |> Enum.sort_by(& &1.title)
  end

  defp show_title(files), do: Enum.find_value(files, & &1.series_title) || "Unknown show"
end
