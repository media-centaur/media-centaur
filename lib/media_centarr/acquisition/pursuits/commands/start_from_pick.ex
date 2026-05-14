defmodule MediaCentarr.Acquisition.Pursuits.Commands.StartFromPick do
  @moduledoc """
  Atomic "first-pick" command — creates a pursuit and its first
  `acquired` target in one transaction, recording `pursuit_started`
  and `release_picked` events.

  Used by `Acquisition.pick_target/2` (manual search → user picks a
  release → Prowlarr.grab succeeds → this command). Replaces the
  previous `Start.execute/1` → `PickTarget.execute/1` pair, which had
  two issues:

    1. Two atoms — if `PickTarget` failed, an orphan pursuit (no
       target) would land in the DB.
    2. `PickTarget` emits `user_decision_recorded` + `fallback_initiated`
       events suitable for the decision-card flow, but spurious on
       first-pick (no decision was shown, no fallback was initiated).

  ## Side effects

  Inside one Repo transaction:

  1. Insert a pursuit with `recipe_type = "prowlarr_query"` and the
     user's typed query.
  2. Insert a target in `acquired` carrying the picked release's
     guid / title / quality.
  3. Update `pursuit.current_target_id` to the new target.
  4. Bump `pursuit.attempt_count` and append the picked guid to
     `tried_release_guids` (so a later `ChangeTarget` won't re-suggest
     the same release).
  5. Record `pursuit_started` + `release_picked` events.

  The caller is responsible for `Prowlarr.grab/1` *before* invoking
  this command — atomicity is bounded to the pursuit + target rows +
  events.
  """

  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Acquisition.Pursuits.{Events, Pursuit}
  alias MediaCentarr.Acquisition.Pursuits.Events.{PursuitStarted, ReleasePicked}
  alias MediaCentarr.Acquisition.{Quality, SearchResult, Target}
  alias MediaCentarr.Repo

  @doc """
  Required args:
    - `:result` — `%SearchResult{}` the user picked.
    - `:manual_query` — the user's typed query (nullable; the pursuit
      stores `nil` when the query was empty/whitespace).

  Optional:
    - `:origin` — `"auto"` or `"manual"`. Defaults to `"manual"` (the
      command exists for the manual-pick flow; auto-picks use
      `Start.execute/1` + the worker path).
  """
  @spec execute(map()) ::
          {:ok, Pursuit.t()} | {:error, Ecto.Changeset.t()}
  def execute(%{result: %SearchResult{} = result, manual_query: manual_query} = args) do
    origin = Map.get(args, :origin, "manual")
    now = DateTime.utc_now(:second)

    result_in_transaction =
      Repo.transaction(fn ->
        with {:ok, pursuit} <- insert_pursuit(result, manual_query, origin),
             {:ok, target} <- insert_acquired_target(pursuit, result, origin),
             {:ok, attempted} <-
               Repo.update(Pursuit.record_attempt_changeset(pursuit, result.guid)),
             {:ok, with_target} <-
               Repo.update(Pursuit.set_current_target_changeset(attempted, target.id)),
             {:ok, _started} <-
               Events.record(%PursuitStarted{
                 pursuit_id: with_target.id,
                 pursuit_title: with_target.title,
                 occurred_at: now,
                 origin: origin
               }),
             {:ok, _picked} <-
               Events.record(%ReleasePicked{
                 pursuit_id: with_target.id,
                 pursuit_title: with_target.title,
                 occurred_at: now,
                 release_title: result.title,
                 guid: result.guid,
                 indexer: result.indexer_name,
                 quality: Quality.label(result.quality),
                 size_bytes: result.size_bytes
               }) do
          with_target
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result_in_transaction do
      {:ok, %Pursuit{title: title}} ->
        Log.info(:acquisition, "pursuit started from pick — #{title} — #{result.title}")

      _ ->
        :ok
    end

    result_in_transaction
  end

  defp insert_pursuit(%SearchResult{title: title}, manual_query, origin) do
    %{
      recipe_type: "prowlarr_query",
      manual_query: manual_query,
      title: title,
      origin: origin
    }
    |> Pursuit.create_changeset()
    |> Repo.insert()
  end

  defp insert_acquired_target(%Pursuit{} = pursuit, %SearchResult{} = result, origin) do
    result
    |> Target.acquired_changeset(pursuit_id: pursuit.id, origin: origin)
    |> Repo.insert()
  end
end
