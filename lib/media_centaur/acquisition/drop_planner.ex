defmodule MediaCentaur.Acquisition.DropPlanner do
  @moduledoc """
  The release-tracking drop→plan pipeline (ADR-056 Phase 2): per
  cadence tick, per tracked title, batches the wants that are **open ∧
  unclaimed ∧ search-due** into one tracking plan and lets the regular
  plan machinery (RunPlan → the approval gate,
  `Reactor.Handlers.plan_changed/1`, reading the stamped
  `approval_policy` → CommitPlan) take it from there.

  Batch is **state, not delta** — every tick re-derives from current
  open-want state, so the pipeline is self-healing: a missed tick, a
  discarded plan, a failed pursuit or a Prowlarr outage all correct
  themselves on the next pass, and the mid-season backlog case is the
  weekly case with more wants.

  Time policy lives here, not in the planner: `WantSchedule` gates
  which wants are searched at all. Every unit is planned at the
  automatic floor (a title's lower-quality acceptance lowers it;
  UIDR-041 §6 removed the patience window). Wants included in a plan
  are stamped `last_searched_at` at creation — the back-off anchor.

  Claims (`Plans.Claims`) make the pipeline safe to run alongside any
  other pursuer: a unit claimed by an active pursuit or a live draft —
  media-search or tracking — is skipped, so double-grabs are
  structurally impossible (and during the legacy-reactor overlap
  window, the legacy pursuit's claim simply wins).
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{AutoGrabSettings, Plans, TitleDownloadParams, WantSchedule}
  alias MediaCentaur.Acquisition.Plans.Claims
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Discovery
  alias MediaCentaur.Format
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.{Identity, Item}
  alias MediaCentaur.Settings.Preferences.PlanningMode

  @doc """
  One pass over every watching item's open wants. Inert without a
  ready Prowlarr (wants accumulate; the next healthy tick plans the
  backlog — nothing is lost).
  """
  @spec run_tick(DateTime.t()) :: :ok
  def run_tick(now \\ DateTime.utc_now(:second)) do
    if Capabilities.prowlarr_ready?() do
      settings = AutoGrabSettings.load()

      ReleaseTracking.list_open_wants()
      |> Enum.group_by(& &1.item_id)
      |> Enum.each(fn {item_id, wants} -> plan_item(item_id, wants, settings, now) end)
    end

    :ok
  end

  defp plan_item(item_id, wants, settings, now) do
    with %Item{} = item <- ReleaseTracking.get_item(item_id),
         true <- Discovery.grabs?(item.tmdb_id, item.media_type) do
      due = Enum.filter(wants, &WantSchedule.due?(&1, now))

      case item.media_type do
        :tv_series ->
          plan_tv_drop(item, due, settings, now)

        :movie ->
          Enum.each(due, &plan_movie_drop(item, &1, settings, now))
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # TV — one drop plan per title covering all due unclaimed wants.
  # ---------------------------------------------------------------------------

  defp plan_tv_drop(_item, [], _settings, _now), do: :ok

  defp plan_tv_drop(item, due_wants, settings, now) do
    tmdb_id = to_string(item.tmdb_id)

    with false <- Plans.active_tracking_draft?(tmdb_id, "tv"),
         claimed = Claims.claimed_units(tmdb_id, "tv"),
         [_ | _] = wants <-
           Enum.reject(due_wants, fn want ->
             MapSet.member?(claimed, {want.season_number, want.episode_number})
           end) do
      {min_quality, max_quality} = bounds(item, settings)
      failed_guids = failed_guids_by_unit(tmdb_id, "tv")

      unit_specs =
        wants
        |> Enum.with_index()
        |> Enum.map(fn {want, index} ->
          %{
            season_number: want.season_number,
            episode_number: want.episode_number,
            air_date: want.air_date,
            label: unit_label(want),
            position: index,
            min_quality: nil,
            excluded_release_guids: Map.get(failed_guids, {want.season_number, want.episode_number}, [])
          }
        end)

      case Plans.create_tracking_plan(
             %{
               identity: Identity.for_item(item),
               tracking_item_id: item.id,
               approval_policy: approval_policy(),
               criteria: %{"min_quality" => min_quality, "max_quality" => max_quality},
               # The item's season sizes are the plan's fit denominator:
               # without them one new episode could take a season pack.
               span_sizes: item.season_sizes
             },
             unit_specs
           ) do
        {:ok, _plan} ->
          ReleaseTracking.mark_wants_searched(Enum.map(wants, & &1.id), now)
          Log.info(:acquisition, "tracking drop plan — #{item.name} (#{length(wants)} units)")

        {:error, reason} ->
          Log.warning(:acquisition, "tracking drop plan failed — #{item.name} — #{inspect(reason)}")
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Movies — one single-unit plan per due want, keyed by the film's own
  # TMDB id (a collection part is its own movie).
  # ---------------------------------------------------------------------------

  defp plan_movie_drop(_item, %{part_tmdb_id: nil}, _settings, _now), do: :ok

  defp plan_movie_drop(item, want, settings, now) do
    tmdb_id = to_string(want.part_tmdb_id)

    with false <- Plans.active_tracking_draft?(tmdb_id, "movie"),
         false <- Claims.claimed_units(tmdb_id, "movie") do
      {min_quality, max_quality} = bounds(item, settings)

      unit_spec = %{
        season_number: nil,
        episode_number: nil,
        label: want.title || item.name,
        position: 0,
        min_quality: nil
      }

      case Plans.create_tracking_plan(
             %{
               identity: Identity.for_want(item, want),
               tracking_item_id: item.id,
               approval_policy: approval_policy(),
               criteria: %{"min_quality" => min_quality, "max_quality" => max_quality}
             },
             [unit_spec]
           ) do
        {:ok, _plan} ->
          ReleaseTracking.mark_wants_searched([want.id], now)
          Log.info(:acquisition, "tracking drop plan — #{want.title || item.name}")

        {:error, reason} ->
          Log.warning(
            :acquisition,
            "tracking drop plan failed — #{want.title || item.name} — #{inspect(reason)}"
          )
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------

  # The Q5 loop-breaker: releases already tried by a previous pursuit of
  # this title are seeded as plan-unit exclusions, so a re-plan only ever
  # assigns genuinely new releases — no grab-regrab loop. The union is
  # per unit identity.
  #
  # This deliberately does not filter on unit state. It used to count
  # only terminally-failed units, reasoning that a satisfied unit's want
  # was closed and so its attempts could not matter. That reasoning is
  # circular: this function is only ever consulted while planning an
  # **open** want, so reaching here at all means the want did not close.
  # A grab that left the want open did not work — whatever it brought
  # back, repeating it cannot help, and a different release might. The
  # cost of the old reading was the same wrong film downloaded once a
  # day for five days.
  defp failed_guids_by_unit(tmdb_id, tmdb_type) do
    import Ecto.Query

    MediaCentaur.Acquisition.Pursuits.Unit
    |> join(:inner, [u], p in MediaCentaur.Acquisition.Pursuits.Pursuit, on: p.id == u.pursuit_id)
    |> where([u, p], p.recipe_type == "tmdb")
    |> where([u, p], p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type)
    |> select([u, _p], {u.season_number, u.episode_number, u.tried_release_guids})
    |> MediaCentaur.Repo.all()
    |> Enum.reduce(%{}, fn {season, episode, guids}, acc ->
      Map.update(acc, {season, episode}, guids || [], &Enum.uniq(&1 ++ (guids || [])))
    end)
  end

  # Who commits the plan is the person's planning mode — the same answer
  # the Download button gives (spec 2026-09-14): manual select parks it
  # for review, auto-select lets the gate commit. Titles that do not grab
  # never reach here (`plan_item/4` guards it).
  defp approval_policy, do: PlanningMode.approval_policy(PlanningMode.value())

  defp bounds(item, settings) do
    params = download_params(item)

    {
      AutoGrabSettings.effective_min_quality(params.min_quality),
      settings.default_max_quality
    }
  end

  # The per-title download params are Acquisition's, keyed by TMDB
  # identity — a tracked title is where they are *used*, never where they
  # are kept.
  defp download_params(%Item{tmdb_id: tmdb_id, media_type: media_type}) do
    TitleDownloadParams.get(tmdb_id, media_type)
  end

  defp unit_label(%{season_number: season, episode_number: episode, title: title}),
    do: Format.episode_label(season, episode, title)
end
