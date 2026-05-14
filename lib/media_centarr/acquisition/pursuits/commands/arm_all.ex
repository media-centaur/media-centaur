defmodule MediaCentarr.Acquisition.Pursuits.Commands.ArmAll do
  @moduledoc """
  Bulk-arms acquisitions for many releases of a single TMDB-tracked
  item — classifies each release against any existing pursuit/target
  and applies the right per-release action.

  Used by `Acquisition.enqueue_all_pending_for_item/1` (which resolves
  ReleaseTracking data and calls this command).

  ## Per-release classification

  For each release in the input list, the command looks up the
  existing pursuit (if any) and its current target, then:

  | existing state                       | action          | summary key      |
  |--------------------------------------|-----------------|------------------|
  | no pursuit                           | `Arm.execute`   | `queued`         |
  | target in `seeking` or `acquired`    | skip            | `in_progress`    |
  | target in `succeeded`                | skip            | `already_grabbed`|
  | target in `failed` / `cancelled`     | `ChangeTarget`  | `rearmed`        |
  | pursuit exists, no current target    | `ChangeTarget`  | `rearmed`        |

  Returns `{:ok, summary}` where summary is a map of counters plus a
  `:failed` list of `{release_key, reason}` tuples for per-release
  errors. Per-release failures don't abort the whole batch — the
  summary aggregates partial successes.
  """

  import Ecto.Query

  alias MediaCentarr.Acquisition.Pursuits.Commands.{Arm, ChangeTarget}
  alias MediaCentarr.Acquisition.Pursuits.Pursuit
  alias MediaCentarr.Acquisition.Target
  alias MediaCentarr.Repo

  @type release :: %{season_number: integer() | nil, episode_number: integer() | nil}
  @type key :: {String.t(), String.t(), integer() | nil, integer() | nil}
  @type summary :: %{
          queued: non_neg_integer(),
          rearmed: non_neg_integer(),
          in_progress: non_neg_integer(),
          already_grabbed: non_neg_integer(),
          failed: [{key(), term()}]
        }

  @doc """
  Required args:
    - `:tmdb_id` (string), `:tmdb_type` (`"movie"|"tv"`), `:name` (string)
    - `:releases` — list of `%{season_number, episode_number}` maps

  Returns `{:ok, summary}`.
  """
  @spec execute(%{
          tmdb_id: String.t(),
          tmdb_type: String.t(),
          name: String.t(),
          releases: [release()]
        }) :: {:ok, summary()}
  def execute(%{tmdb_id: tmdb_id, tmdb_type: tmdb_type, name: name, releases: releases})
      when is_binary(tmdb_id) and is_binary(tmdb_type) and is_binary(name) and is_list(releases) do
    keys = Enum.map(releases, &release_key(&1, tmdb_id, tmdb_type))
    status_map = statuses_for_releases(keys)

    summary =
      Enum.reduce(releases, empty_summary(), fn release, acc ->
        key = release_key(release, tmdb_id, tmdb_type)
        classify_and_apply(acc, key, release, tmdb_id, tmdb_type, name, Map.get(status_map, key))
      end)

    {:ok, summary}
  end

  defp release_key(release, tmdb_id, tmdb_type) do
    {tmdb_id, tmdb_type, release.season_number, release.episode_number}
  end

  defp empty_summary do
    %{queued: 0, rearmed: 0, in_progress: 0, already_grabbed: 0, failed: []}
  end

  @doc """
  Batch lookup: given a list of `(tmdb_id, tmdb_type, season_number,
  episode_number)` keys, returns a map keyed by the same tuple →
  `{pursuit, current_target | nil}`.

  Exposed because the upcoming-zone renderer also uses this batched
  shape to decorate each release card with its acquisition status
  without N+1ing the DB. Internal callers stay on the private
  `statuses_for_keys/1` helper.
  """
  @spec statuses_for_releases([key()]) :: %{key() => {Pursuit.t(), Target.t() | nil}}
  def statuses_for_releases([]), do: %{}

  def statuses_for_releases(keys) when is_list(keys) do
    # SQL-side tuple filter: build an OR-chain of exact-tuple matches so
    # the DB returns only requested rows. Prior implementation widened
    # the WHERE to `tmdb_id in ^ids and tmdb_type in ^types`, then
    # dropped non-requested tuples in BEAM — a wasted round-trip when a
    # series has many pursuits but only a few requested episodes.
    predicate =
      Enum.reduce(keys, dynamic(false), fn key, acc ->
        dynamic([p], ^acc or ^key_predicate(key))
      end)

    pursuits =
      Pursuit
      |> where([p], p.recipe_type == "tmdb")
      |> where(^predicate)
      |> Repo.all()

    target_ids = pursuits |> Enum.map(& &1.current_target_id) |> Enum.reject(&is_nil/1)
    targets_by_id = targets_by_id(target_ids)

    Map.new(pursuits, fn pursuit ->
      key = {pursuit.tmdb_id, pursuit.tmdb_type, pursuit.season_number, pursuit.episode_number}
      target = Map.get(targets_by_id, pursuit.current_target_id)
      {key, {pursuit, target}}
    end)
  end

  # One dynamic per nil/non-nil shape so Ecto sees only top-level
  # `^interpolation`s in the outer `dynamic`.
  defp key_predicate({id, type, nil, nil}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        is_nil(p.season_number) and is_nil(p.episode_number)
    )
  end

  defp key_predicate({id, type, season, nil}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        p.season_number == ^season and is_nil(p.episode_number)
    )
  end

  defp key_predicate({id, type, nil, episode}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        is_nil(p.season_number) and p.episode_number == ^episode
    )
  end

  defp key_predicate({id, type, season, episode}) do
    dynamic(
      [p],
      p.tmdb_id == ^id and p.tmdb_type == ^type and
        p.season_number == ^season and p.episode_number == ^episode
    )
  end

  defp targets_by_id([]), do: %{}

  defp targets_by_id(ids) do
    Target
    |> where([t], t.id in ^ids)
    |> Repo.all()
    |> Map.new(fn target -> {target.id, target} end)
  end

  defp classify_and_apply(acc, key, release, tmdb_id, tmdb_type, name, nil) do
    case Arm.execute(%{
           tmdb_id: tmdb_id,
           tmdb_type: tmdb_type,
           title: name,
           season_number: release.season_number,
           episode_number: release.episode_number
         }) do
      {:ok, _target} -> %{acc | queued: acc.queued + 1}
      {:error, reason} -> %{acc | failed: [{key, reason} | acc.failed]}
    end
  end

  defp classify_and_apply(acc, key, _release, _tmdb_id, _tmdb_type, _name, {pursuit, target}) do
    classify_target(acc, key, pursuit, target)
  end

  defp classify_target(acc, _key, _pursuit, %Target{status: "succeeded"}),
    do: %{acc | already_grabbed: acc.already_grabbed + 1}

  defp classify_target(acc, _key, _pursuit, %Target{status: "acquired"}),
    do: %{acc | in_progress: acc.in_progress + 1}

  defp classify_target(acc, _key, _pursuit, %Target{status: "seeking"}),
    do: %{acc | in_progress: acc.in_progress + 1}

  defp classify_target(acc, key, pursuit, _target) do
    # Failed, cancelled, or nil — pivot the pursuit to a new target.
    case ChangeTarget.execute(%{pursuit_id: pursuit.id}) do
      {:ok, _pursuit} -> %{acc | rearmed: acc.rearmed + 1}
      {:error, reason} -> %{acc | failed: [{key, reason} | acc.failed]}
    end
  end
end
