defmodule MediaCentaur.Acquisition.Plans do
  @moduledoc """
  The durable draft plan context (media-search campaign Phase 3):
  creation from a targeting selection, the feedback verbs the user
  steers with (exclude a release, exclude a unit, force a re-plan),
  and approval/discard. The autonomous search-and-solve lives in
  `Acquisition.Jobs.RunPlan`; commit-to-pursuit in
  `Plans.Commands.CommitPlan`; the coverage-board view-model in
  `Plans.Board`; the swap picker and gap evidence in
  `Plans.Alternatives`.

  Every mutation broadcasts `PlanEvents.Changed` on
  `acquisition:updates` so live surfaces re-read; the rows themselves
  are the state of record (durable draft — refresh-safe by design).
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.Jobs.RunPlan
  alias MediaCentaur.Acquisition.PlanEvents
  alias MediaCentaur.Acquisition.Plans.{CommitPlan, DownloadScope, Plan, PlanUnit}
  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.Format
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  @type unit_choice :: {pos_integer(), pos_integer()}

  @doc """
  Creates a draft plan for a series selection and the user's chosen
  units, then starts the autonomous planning run. Units carry their
  picker labels so the board reads like the picker did.
  `approval_policy:` (`"automatic"` | `"review"`, default review) names
  who commits the plan once ready — see `Plan`.
  """
  @spec create_series_plan(Targeting.Selection.t(), [unit_choice()], keyword()) ::
          {:ok, Plan.t()} | {:error, term()}
  def create_series_plan(%Targeting.Selection{} = selection, unit_choices, opts \\ []) do
    episodes =
      for season <- selection.seasons, episode <- season.episodes, into: %{} do
        {{episode.season_number, episode.episode_number}, episode}
      end

    unit_specs =
      unit_choices
      |> Enum.with_index()
      |> Enum.map(fn {{season, episode}, index} ->
        selected = Map.get(episodes, {season, episode})

        %{
          season_number: season,
          episode_number: episode,
          air_date: selected && selected.air_date,
          label: Format.episode_label(season, episode, selected && selected.label),
          position: index
        }
      end)

    create_plan(
      %{
        tmdb_id: selection.tmdb_id,
        tmdb_type: "tv",
        title: selection.title,
        origin_country: selection.origin_country,
        criteria: Keyword.get(opts, :criteria, %{}),
        span_sizes: Targeting.aired_counts(selection),
        grab_future: Keyword.get(opts, :grab_future, false),
        approval_policy: Keyword.get(opts, :approval_policy, "review")
      },
      unit_specs
    )
  end

  @doc """
  Creates a single-unit movie plan and starts the planning run.
  `approval_policy:` (`"automatic"` | `"review"`, default review) names
  who commits the plan once ready — see `Plan`.
  """
  @spec create_movie_plan(map(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def create_movie_plan(%{tmdb_id: tmdb_id, title: title} = attrs, opts \\ []) do
    create_plan(
      %{
        tmdb_id: to_string(tmdb_id),
        tmdb_type: "movie",
        title: title,
        year: Map.get(attrs, :year),
        criteria: Keyword.get(opts, :criteria, %{}),
        grab_future: Keyword.get(opts, :grab_future, false),
        approval_policy: Keyword.get(opts, :approval_policy, "review")
      },
      [%{season_number: nil, episode_number: nil, label: title, position: 0}]
    )
  end

  @doc """
  Plans a TMDB title from its snapshot alone (spec 2026-09-05 §17): the
  door a surface that lists titles the library does not own uses, where
  there is no picker. Runs on the context task supervisor — a series
  needs a targeting fetch, and the work must outlive the calling
  LiveView (ADR-049) — and returns as soon as it is queued; the plan row
  broadcasts on `acquisition:updates` when it exists. Movies take the
  same path so the contract is one shape.

  Options: `approval_policy:` (`"automatic"` | `"review"`, default
  review — the one-click download passes automatic); `scope:` (series
  only) `:first_season` (default) or `:everything`, see `DownloadScope`.
  `:everything` also starts release tracking for the title so new
  episodes follow; an already-tracked title is left alone. The plan is
  created before tracking so its units are not excluded as tracked.

  A failure inside the task (TMDB unreachable, nothing pickable) is
  logged at warning on `:acquisition` and leaves no plan.
  """
  @spec plan_title(Title.t(), keyword()) :: :ok
  def plan_title(%Title{} = title, opts \\ []) do
    policy = Keyword.get(opts, :approval_policy, "review")
    scope = Keyword.get(opts, :scope, :first_season)

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      do_plan_title(title, policy, scope)
    end)

    :ok
  end

  defp do_plan_title(%Title{media_type: :movie} = title, policy, _scope) do
    case create_movie_plan(
           %{tmdb_id: title.tmdb_id, title: title.name, year: title_year(title)},
           approval_policy: policy
         ) do
      {:ok, _plan} ->
        :ok

      {:error, reason} ->
        Log.warning(:acquisition, "could not plan — #{title.name} — #{inspect(reason)}")
    end
  end

  defp do_plan_title(%Title{media_type: :tv_series} = title, policy, scope) do
    with {:ok, selection} <- Targeting.series_selection(title.tmdb_id),
         units when units != [] <- DownloadScope.units(selection, scope),
         {:ok, _plan} <- create_series_plan(selection, units, approval_policy: policy) do
      if scope == :everything, do: ensure_tracked(title)
      :ok
    else
      [] ->
        Log.warning(:acquisition, "nothing to plan — #{title.name}")

      {:error, reason} ->
        Log.warning(:acquisition, "could not plan — #{title.name} — #{inspect(reason)}")
    end
  end

  defp ensure_tracked(%Title{} = title) do
    case ReleaseTracking.get_item_by_tmdb(title.tmdb_id, :tv_series) do
      nil -> ReleaseTracking.track_from_search(title)
      _item -> :ok
    end
  end

  defp title_year(%Title{year: year}) when is_binary(year) do
    case Integer.parse(year) do
      {parsed, ""} -> parsed
      _other -> nil
    end
  end

  defp title_year(_title), do: nil

  @doc """
  Creates a release-tracking drop plan (ADR-056 Phase 2) and starts the
  planning run. `plan_attrs` carries the tmdb identity plus
  `tracking_item_id`; `unit_specs` come from the item's due wants and
  may carry per-unit `min_quality` floors (the patience elevation,
  stamped by the drop planner so the planner stays time-blind).
  """
  @spec create_tracking_plan(map(), [map()]) :: {:ok, Plan.t()} | {:error, term()}
  def create_tracking_plan(plan_attrs, unit_specs) do
    plan_attrs
    |> Map.put_new(:origin, "tracking")
    |> create_plan(unit_specs)
  end

  @doc """
  Whether a live tracking draft (planning or ready) already exists for
  this tmdb identity — the one-active-draft-per-title rule (ADR-056
  Q2): wants opening mid-draft wait for the next tick rather than
  mutating a plan under review.
  """
  @spec active_tracking_draft?(String.t(), String.t()) :: boolean()
  def active_tracking_draft?(tmdb_id, tmdb_type) do
    Plan
    |> where([p], p.origin == "tracking" and p.status in ["planning", "ready"])
    |> where([p], p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type)
    |> Repo.exists?()
  end

  @doc """
  The tracking item id behind a committed pursuit, when the pursuit was
  born from a plan carrying tracking provenance — the cancel-dismisses
  back-pointer. Covers both automated drop plans (origin "tracking")
  and user-initiated "plan now" drafts (origin "manual" with a
  tracking_item_id). Nil for plain media-search and legacy pursuits.
  """
  @spec tracking_item_id_for_pursuit(Ecto.UUID.t()) :: Ecto.UUID.t() | nil
  def tracking_item_id_for_pursuit(pursuit_id) do
    Plan
    |> where([p], p.pursuit_id == ^pursuit_id and not is_nil(p.tracking_item_id))
    |> select([p], p.tracking_item_id)
    |> limit(1)
    |> Repo.one()
  end

  defp create_plan(plan_attrs, unit_specs) do
    if unit_specs == [] do
      {:error, :no_units}
    else
      result =
        Repo.transaction(fn ->
          with {:ok, plan} <- Repo.insert(Plan.create_changeset(resolve_title_bounds(plan_attrs))),
               :ok <- insert_units(plan, unit_specs) do
            plan
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      with {:ok, plan} <- result do
        Oban.insert(RunPlan.new(%{"plan_id" => plan.id}))
        broadcast_changed(plan)
        {:ok, plan}
      end
    end
  end

  # A manual plan with no explicit bounds snapshots the tracked title's
  # per-title quality preferences when the title is tracked (ADR-063 §2:
  # bounds resolve unit override → per-title preference → global
  # default; `criteria` is the per-plan snapshot of the middle layer).
  defp resolve_title_bounds(%{criteria: criteria} = plan_attrs) when criteria == %{} do
    case tracking_item_for(plan_attrs) do
      %{min_quality: min, max_quality: max} when is_binary(min) or is_binary(max) ->
        bounds =
          %{}
          |> put_bound("min_quality", min)
          |> put_bound("max_quality", max)

        %{plan_attrs | criteria: bounds}

      _untracked_or_unset ->
        plan_attrs
    end
  end

  defp resolve_title_bounds(plan_attrs), do: plan_attrs

  defp tracking_item_for(%{tmdb_id: tmdb_id, tmdb_type: tmdb_type}) do
    with {numeric_id, ""} <- Integer.parse(to_string(tmdb_id)),
         {:ok, media_type} <- item_media_type(tmdb_type) do
      ReleaseTracking.get_item_by_tmdb(numeric_id, media_type)
    else
      _no_identity -> nil
    end
  end

  defp item_media_type("tv"), do: {:ok, :tv_series}
  defp item_media_type("movie"), do: {:ok, :movie}
  defp item_media_type(_other), do: :error

  defp put_bound(bounds, _key, nil), do: bounds
  defp put_bound(bounds, key, value), do: Map.put(bounds, key, value)

  defp insert_units(plan, unit_specs) do
    Enum.reduce_while(unit_specs, :ok, fn spec, :ok ->
      case Repo.insert(PlanUnit.create_changeset(Map.put(spec, :plan_id, plan.id))) do
        {:ok, _unit} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Reads
  # ---------------------------------------------------------------------------

  @spec fetch(Ecto.UUID.t()) :: {:ok, Plan.t()} | {:error, :not_found}
  def fetch(id) do
    case Repo.get(Plan, id) do
      nil -> {:error, :not_found}
      %Plan{} = plan -> {:ok, plan}
    end
  end

  @doc "The plan's units in display order."
  @spec units_for(Ecto.UUID.t()) :: [PlanUnit.t()]
  def units_for(plan_id) do
    PlanUnit
    |> where([u], u.plan_id == ^plan_id)
    |> order_by([u], asc: u.position, asc: u.inserted_at)
    |> Repo.all()
  end

  @doc """
  Whether a solved plan is clean: every wanted unit (every unit not
  excluded) was found within the plan's quality bounds — no gaps, no
  below-preference units, no pack offers. The approval gate's
  qualifying test for a manual plan with `approval_policy: "automatic"`.
  Reads the units directly so the context stays free of the board
  view-model.
  """
  @spec clean?(Plan.t()) :: boolean()
  def clean?(%Plan{id: plan_id}) do
    plan_id
    |> units_for()
    |> Enum.reject(&(&1.status == "excluded"))
    |> case do
      [] -> false
      wanted -> Enum.all?(wanted, &(&1.status == "found"))
    end
  end

  @doc "Draft plans still in flight (planning or ready), newest first."
  @spec list_drafts() :: [Plan.t()]
  def list_drafts do
    Plan
    |> where([p], p.status in ["planning", "ready"])
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  How many plans are waiting on a person: status `ready`, any origin.
  The Incoming follow-up pill's source (`MediaCentaurWeb.ShellBadges`).
  """
  @spec count_awaiting_review() :: non_neg_integer()
  def count_awaiting_review do
    Plan
    |> where([p], p.status == "ready")
    |> Repo.aggregate(:count)
  end

  # ---------------------------------------------------------------------------
  # Feedback verbs
  # ---------------------------------------------------------------------------

  @doc """
  "Not this release" for one unit: records the exclusion, resets the
  unit to pending, and re-plans from the corpus (no forced re-search —
  swapping resolves among already-known candidates first).
  """
  @spec exclude_release(Ecto.UUID.t(), String.t()) :: {:ok, Plan.t()} | {:error, term()}
  def exclude_release(plan_unit_id, guid) do
    with {:ok, unit} <- fetch_unit(plan_unit_id),
         {:ok, plan} <- fetch(unit.plan_id),
         {:ok, _unit} <- Repo.update(PlanUnit.exclude_release_changeset(unit, guid)) do
      replan(plan)
    end
  end

  @doc "User opt-out of one unit — the plan stops wanting it."
  @spec exclude_unit(Ecto.UUID.t()) :: {:ok, Plan.t()} | {:error, term()}
  def exclude_unit(plan_unit_id) do
    with {:ok, unit} <- fetch_unit(plan_unit_id),
         {:ok, plan} <- fetch(unit.plan_id),
         {:ok, _unit} <- Repo.update(PlanUnit.exclude_unit_changeset(unit)) do
      replan(plan)
    end
  end

  @doc """
  Forces a fresh planning pass. `force_search: true` bypasses the
  corpus freshness gate (the user-initiated "search again").
  """
  @spec replan(Plan.t(), keyword()) :: {:ok, Plan.t()} | {:error, term()}
  def replan(%Plan{} = plan, opts \\ []) do
    with {:ok, planning} <-
           Repo.update(Plan.transition_changeset(plan, "planning", ["planning", "ready"])) do
      Oban.insert(
        RunPlan.new(%{"plan_id" => planning.id, "force" => Keyword.get(opts, :force_search, false)})
      )

      broadcast_changed(planning)
      {:ok, planning}
    end
  end

  @doc """
  The per-title acceptance (ADR-063 §2, UIDR-029): the user has said
  lower-quality releases are fine for this title. Ensures the title is
  tracked, stores `min_quality: "any"` as its durable per-title
  preference, snapshots the accepted bound onto this plan, and
  re-solves so the below-preference releases become assignable. The
  global default is never touched.
  """
  @spec accept_lower_quality(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def accept_lower_quality(%Plan{} = plan) do
    with {:ok, item} <- ensure_tracking_item(plan),
         {:ok, _item} <- ReleaseTracking.update_auto_grab(item, %{min_quality: "any"}),
         {:ok, snapshotted} <-
           Repo.update(
             Plan.criteria_changeset(plan, Map.put(plan.criteria || %{}, "min_quality", "any"))
           ) do
      replan(snapshotted)
    end
  end

  @doc """
  Reverses `accept_lower_quality/1`: clears the title's per-title
  acceptance (back to inheriting the global default), drops the plan's
  snapshot, and re-solves. The tracking item itself stays — untracking
  is a separate, deliberate act.
  """
  @spec undo_lower_quality(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def undo_lower_quality(%Plan{} = plan) do
    with {:ok, item} <- ensure_tracking_item(plan),
         {:ok, _item} <- ReleaseTracking.update_auto_grab(item, %{min_quality: nil}),
         {:ok, snapshotted} <-
           Repo.update(Plan.criteria_changeset(plan, Map.delete(plan.criteria || %{}, "min_quality"))) do
      replan(snapshotted)
    end
  end

  defp ensure_tracking_item(%Plan{} = plan) do
    case tracking_item_for(plan) do
      nil ->
        with {numeric_id, ""} <- Integer.parse(to_string(plan.tmdb_id)),
             {:ok, media_type} <- item_media_type(plan.tmdb_type) do
          ReleaseTracking.track_item(%{
            tmdb_id: numeric_id,
            media_type: media_type,
            name: plan.title,
            source: :manual,
            origin_country: plan.origin_country
          })
        else
          _no_identity -> {:error, :no_tmdb_identity}
        end

      item ->
        {:ok, item}
    end
  end

  @doc "Commits a ready plan as one composite pursuit. See `CommitPlan`."
  @spec approve(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def approve(%Plan{} = plan), do: CommitPlan.execute(plan)

  @doc "Discards a draft plan (terminal; rows are kept for the record)."
  @spec discard(Plan.t()) :: {:ok, Plan.t()} | {:error, term()}
  def discard(%Plan{} = plan) do
    with {:ok, discarded} <-
           Repo.update(Plan.transition_changeset(plan, "discarded", ["planning", "ready"])) do
      broadcast_changed(discarded)
      {:ok, discarded}
    end
  end

  @doc """
  Deletes a tracking draft outright — used by the mode gate when a drop
  plan solves to zero found units. Unlike user-facing discards there is
  no record value in an automated tick that found nothing (the wants
  remain the durable intent, stamped searched), and the cadence would
  otherwise accrete discarded rows every interval an unfound want
  retries.
  """
  @spec delete_tracking_draft(Plan.t()) :: :ok
  def delete_tracking_draft(%Plan{origin: "tracking"} = plan) do
    Repo.delete_all(where(PlanUnit, [u], u.plan_id == ^plan.id))
    Repo.delete_all(where(Plan, [p], p.id == ^plan.id))
    broadcast_changed(%{plan | status: "discarded"})
    :ok
  end

  @spec fetch_unit(Ecto.UUID.t()) :: {:ok, PlanUnit.t()} | {:error, :not_found}
  def fetch_unit(plan_unit_id) do
    case Repo.get(PlanUnit, plan_unit_id) do
      nil -> {:error, :not_found}
      %PlanUnit{} = unit -> {:ok, unit}
    end
  end

  @doc "Broadcasts `PlanEvents.Changed` for the plan on `acquisition:updates`."
  @spec broadcast_changed(Plan.t()) :: :ok
  def broadcast_changed(%Plan{} = plan) do
    Topics.publish(
      Topics.acquisition_updates(),
      %PlanEvents.Changed{plan_id: plan.id, status: plan.status}
    )

    :ok
  end
end
