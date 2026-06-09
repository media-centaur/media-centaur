defmodule MediaCentaur.Acquisition.Pursuits.Commands.StartFromPick do
  @moduledoc """
  Atomic "first-pick" command — creates a pursuit, one unit per picked
  release, and the `acquired` targets covering them, in one
  transaction, recording `pursuit_started` and per-pick
  `release_picked` events.

  Used by `Acquisition.pick_targets/2` (manual search → user picks
  releases → Prowlarr.grab succeeds per release → this command). A
  brace-expanded batch (`Sample Show S01E{01-03}` with three picks)
  collapses into **one composite pursuit with three units** (ADR-055)
  — each unit carries the expanded term that produced its result as
  its concrete `query`, so per-unit re-search stays scoped.

  ## Side effects

  Inside one Repo transaction:

  1. Insert a pursuit with `recipe_type = "prowlarr_query"` and the
     user's typed (possibly braced) query. A single pick keeps the
     picked release's title as the pursuit title (legacy naming); a
     multi-pick batch is named for the braced query — the user's
     intent.
  2. Per pick, in selection order: insert a unit carrying the expanded
     term, insert a target in `acquired` covering it, point
     `unit.current_target_id` at it, bump `unit.attempt_count`, append
     the picked guid to `unit.tried_release_guids`, and record a
     `release_picked` event.

  The caller is responsible for `Prowlarr.grab/1` per release *before*
  invoking this command — only successfully-grabbed picks belong in
  `:picks`. Atomicity is bounded to the pursuit + unit + target rows +
  events.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Pursuits.{Events, Pursuit, TargetUnit, Unit}
  alias MediaCentaur.Acquisition.Pursuits.Events.{PursuitStarted, ReleasePicked}
  alias MediaCentaur.Acquisition.{InfoHash, Target}
  alias MediaCentaur.Search.{Quality, SearchResult}
  alias MediaCentaur.Repo

  @type pick :: %{term: String.t() | nil, result: SearchResult.t()}

  @doc """
  Two call shapes:

  - **Single pick** `%{result, manual_query[, origin]}` — kept for the
    decision-card and legacy call shape. Equivalent to a one-element
    `:picks` batch; returns `{:ok, pursuit}`.
  - **Batch** `%{picks, manual_query[, origin]}` — `:picks` is a
    non-empty list of `%{term, result}` (the expanded query term and
    the `%SearchResult{}` the user picked for it). Returns
    `{:ok, %{pursuit: pursuit, targets: targets}}` with targets in
    pick order.

  `:origin` defaults to `"manual"` in both shapes.
  """
  @spec execute(%{result: SearchResult.t(), manual_query: String.t() | nil}) ::
          {:ok, Pursuit.t()} | {:error, Ecto.Changeset.t()}
  @spec execute(%{picks: [pick()], manual_query: String.t() | nil}) ::
          {:ok, %{pursuit: Pursuit.t(), targets: [Target.t()]}} | {:error, Ecto.Changeset.t()}
  def execute(%{result: %SearchResult{} = result, manual_query: manual_query} = args) do
    batch_args = %{
      picks: [%{term: manual_query, result: result}],
      manual_query: manual_query,
      origin: Map.get(args, :origin, "manual")
    }

    with {:ok, %{pursuit: pursuit}} <- execute(batch_args), do: {:ok, pursuit}
  end

  def execute(%{picks: [_ | _] = picks, manual_query: manual_query} = args) do
    origin = Map.get(args, :origin, "manual")
    now = DateTime.utc_now(:second)

    result_in_transaction =
      Repo.transaction(fn ->
        with {:ok, pursuit} <- insert_pursuit(picks, manual_query, origin),
             {:ok, targets} <- insert_picked_units(pursuit, picks, origin, now),
             {:ok, _started} <-
               Events.record(%PursuitStarted{
                 pursuit_id: pursuit.id,
                 pursuit_title: pursuit.title,
                 occurred_at: now,
                 origin: origin
               }) do
          %{pursuit: pursuit, targets: targets}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result_in_transaction do
      {:ok, %{pursuit: %Pursuit{title: title}, targets: targets}} ->
        Log.info(
          :acquisition,
          "pursuit started from pick — #{title} — #{length(targets)} release(s)"
        )

      _ ->
        :ok
    end

    result_in_transaction
  end

  defp insert_pursuit(picks, manual_query, origin) do
    %{
      recipe_type: "prowlarr_query",
      manual_query: manual_query,
      title: pursuit_title(picks, manual_query),
      origin: origin
    }
    |> Pursuit.create_changeset()
    |> Repo.insert()
  end

  # A single pick keeps the release title (legacy naming); a batch is
  # named for the braced query — the user's intent, not any one release.
  defp pursuit_title([%{result: %SearchResult{title: title}}], _manual_query), do: title
  defp pursuit_title([%{result: %SearchResult{title: title}} | _], nil), do: title
  defp pursuit_title(_picks, manual_query), do: manual_query

  defp insert_picked_units(pursuit, picks, origin, now) do
    picks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {pick, index}, {:ok, targets} ->
      case insert_picked_unit(pursuit, pick, index, origin, now) do
        {:ok, target} -> {:cont, {:ok, [target | targets]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, targets} -> {:ok, Enum.reverse(targets)}
      error -> error
    end
  end

  defp insert_picked_unit(pursuit, %{term: term, result: result}, index, origin, now) do
    torrent_hash = InfoHash.resolve(result)

    with {:ok, unit} <-
           Repo.insert(
             Unit.create_changeset(%{
               pursuit_id: pursuit.id,
               query: term,
               label: term,
               position: index
             })
           ),
         {:ok, target} <-
           result
           |> Target.acquired_changeset(
             pursuit_id: pursuit.id,
             origin: origin,
             torrent_hash: torrent_hash
           )
           |> Repo.insert(),
         {:ok, _coverage} <-
           Repo.insert(TargetUnit.create_changeset(%{target_id: target.id, unit_id: unit.id})),
         {:ok, attempted} <- Repo.update(Unit.record_attempt_changeset(unit, result.guid)),
         {:ok, _with_target} <-
           Repo.update(Unit.set_current_target_changeset(attempted, target.id)),
         {:ok, _picked} <-
           Events.record(%ReleasePicked{
             pursuit_id: pursuit.id,
             pursuit_title: pursuit.title,
             occurred_at: now,
             release_title: result.title,
             guid: result.guid,
             indexer: result.indexer_name,
             quality: Quality.label(result.quality),
             size_bytes: result.size_bytes
           }) do
      {:ok, target}
    end
  end
end
