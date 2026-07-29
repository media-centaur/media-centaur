defmodule MediaCentaur.Acquisition.DropPlanner do
  @moduledoc """
  The release-tracking drop→plan pipeline (ADR-056 Phase 2): per
  cadence tick, per tracked title, batches the wants that are **open ∧
  unclaimed ∧ search-due** into one tracking plan and lets the regular
  plan machinery (RunPlan → mode gate → CommitPlan) take it from there.

  Batch is **state, not delta** — every tick re-derives from current
  open-want state, so the pipeline is self-healing: a missed tick, a
  discarded plan, a failed pursuit or a Prowlarr outage all correct
  themselves on the next pass, and the mid-season backlog case is the
  weekly case with more wants.

  Time policy lives here, not in the planner: a want inside its
  patience window gets its quality floor stamped to the ceiling on the
  plan unit (`min_quality`), and `WantSchedule` gates which wants are
  searched at all. Wants included in a plan are stamped
  `last_searched_at` at creation — the back-off anchor.

  Claims (`Plans.Claims`) make the pipeline safe to run alongside any
  other pursuer: a unit claimed by an active pursuit or a live draft —
  media-search or tracking — is skipped, so double-grabs are
  structurally impossible (and during the legacy-reactor overlap
  window, the legacy pursuit's claim simply wins).
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.{AutoGrabSettings, Plans, WantSchedule}
  alias MediaCentaur.Acquisition.Plans.Claims
  alias MediaCentaur.Capabilities
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Item
  alias MediaCentaur.Search.Quality

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

  @doc """
  User-initiated "plan now" for one tracked item (replaces the legacy
  bulk-arm button): plans ALL of the item's open unclaimed wants
  immediately — no due-ness gate, no patience floors (the user asked
  for what's available now), and as an origin-"manual" draft with
  tracking provenance, so the mode gate leaves it `ready` for the
  user's approval regardless of the item's auto-grab mode.
  """
  @spec plan_item_now(Ecto.UUID.t(), DateTime.t()) ::
          {:ok, :planned} | {:ok, :nothing_pending} | {:error, term()}
  def plan_item_now(item_id, now \\ DateTime.utc_now(:second)) do
    case ReleaseTracking.get_item(item_id) do
      nil ->
        {:error, :not_found}

      item ->
        if Capabilities.prowlarr_ready?() do
          # Defensive sync: the user may click right after tracking,
          # before any sweep has opened the wants.
          :ok = ReleaseTracking.sync_wants(item)
          plan_now(item, ReleaseTracking.open_wants_for_item(item.id), now)
        else
          {:error, :acquisition_unavailable}
        end
    end
  end

  defp plan_now(_item, [], _now), do: {:ok, :nothing_pending}

  defp plan_now(%Item{media_type: :tv_series} = item, wants, now) do
    tmdb_id = to_string(item.tmdb_id)
    claimed = Claims.claimed_units(tmdb_id, "tv")

    unclaimed =
      Enum.reject(wants, fn want ->
        MapSet.member?(claimed, {want.season_number, want.episode_number})
      end)

    if unclaimed == [] or Plans.active_tracking_draft?(tmdb_id, "tv") do
      {:ok, :nothing_pending}
    else
      {min_quality, max_quality} = bounds(item, AutoGrabSettings.load())

      unit_specs =
        unclaimed
        |> Enum.with_index()
        |> Enum.map(fn {want, index} ->
          %{
            season_number: want.season_number,
            episode_number: want.episode_number,
            air_date: want.air_date,
            label: unit_label(want),
            position: index
          }
        end)

      case Plans.create_tracking_plan(
             %{
               tmdb_id: tmdb_id,
               tmdb_type: "tv",
               title: item.name,
               origin_country: item.origin_country,
               tracking_item_id: item.id,
               origin: "manual",
               criteria: %{"min_quality" => min_quality, "max_quality" => max_quality}
             },
             unit_specs
           ) do
        {:ok, _plan} ->
          ReleaseTracking.mark_wants_searched(Enum.map(unclaimed, & &1.id), now)
          {:ok, :planned}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp plan_now(%Item{media_type: :movie} = item, wants, now) do
    plannable =
      Enum.reject(wants, fn want ->
        is_nil(want.part_tmdb_id) or
          Claims.claimed_units(to_string(want.part_tmdb_id), "movie") or
          Plans.active_tracking_draft?(to_string(want.part_tmdb_id), "movie")
      end)

    if plannable == [] do
      {:ok, :nothing_pending}
    else
      {min_quality, max_quality} = bounds(item, AutoGrabSettings.load())

      Enum.each(plannable, fn want ->
        {:ok, _plan} =
          Plans.create_tracking_plan(
            %{
              tmdb_id: to_string(want.part_tmdb_id),
              tmdb_type: "movie",
              title: want.title || item.name,
              year: want.air_date && want.air_date.year,
              tracking_item_id: item.id,
              origin: "manual",
              criteria: %{"min_quality" => min_quality, "max_quality" => max_quality}
            },
            [
              %{
                season_number: nil,
                episode_number: nil,
                label: want.title || item.name,
                position: 0
              }
            ]
          )

        ReleaseTracking.mark_wants_searched([want.id], now)
      end)

      {:ok, :planned}
    end
  end

  defp plan_item(item_id, wants, settings, now) do
    with %Item{} = item <- ReleaseTracking.get_item(item_id),
         mode when mode != "off" <- AutoGrabSettings.effective_mode(item.auto_grab_mode, settings) do
      patience = AutoGrabSettings.effective_patience_hours(item.quality_4k_patience_hours, settings)
      due = Enum.filter(wants, &WantSchedule.due?(&1, patience, now))

      case item.media_type do
        :tv_series ->
          plan_tv_drop(item, due, settings, patience, now)

        :movie ->
          Enum.each(due, &plan_movie_drop(item, &1, settings, patience, now))
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # TV — one drop plan per title covering all due unclaimed wants.
  # ---------------------------------------------------------------------------

  defp plan_tv_drop(_item, [], _settings, _patience, _now), do: :ok

  defp plan_tv_drop(item, due_wants, settings, patience, now) do
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
            min_quality: floor_for(want, patience, min_quality, max_quality, now),
            excluded_release_guids: Map.get(failed_guids, {want.season_number, want.episode_number}, [])
          }
        end)

      case Plans.create_tracking_plan(
             %{
               tmdb_id: tmdb_id,
               tmdb_type: "tv",
               title: item.name,
               origin_country: item.origin_country,
               tracking_item_id: item.id,
               criteria: %{"min_quality" => min_quality, "max_quality" => max_quality}
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

  defp plan_movie_drop(_item, %{part_tmdb_id: nil}, _settings, _patience, _now), do: :ok

  defp plan_movie_drop(item, want, settings, patience, now) do
    tmdb_id = to_string(want.part_tmdb_id)

    with false <- Plans.active_tracking_draft?(tmdb_id, "movie"),
         false <- Claims.claimed_units(tmdb_id, "movie") do
      {min_quality, max_quality} = bounds(item, settings)

      unit_spec = %{
        season_number: nil,
        episode_number: nil,
        label: want.title || item.name,
        position: 0,
        min_quality: floor_for(want, patience, min_quality, max_quality, now)
      }

      case Plans.create_tracking_plan(
             %{
               tmdb_id: tmdb_id,
               tmdb_type: "movie",
               title: want.title || item.name,
               year: want.air_date && want.air_date.year,
               tracking_item_id: item.id,
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

  # The Q5 loop-breaker: releases already tried by terminally-failed
  # pursuit units of this title are seeded as plan-unit exclusions, so
  # a re-plan only ever assigns genuinely new releases — no
  # grab-fail-regrab loop. Satisfied units' attempts are irrelevant
  # (their wants are closed); the union is per unit identity.
  defp failed_guids_by_unit(tmdb_id, tmdb_type) do
    import Ecto.Query

    terminal_failure = MediaCentaur.Acquisition.Pursuits.UnitState.terminal_failure()

    MediaCentaur.Acquisition.Pursuits.Unit
    |> join(:inner, [u], p in MediaCentaur.Acquisition.Pursuits.Pursuit, on: p.id == u.pursuit_id)
    |> where([u, p], p.recipe_type == "tmdb")
    |> where([u, p], p.tmdb_id == ^tmdb_id and p.tmdb_type == ^tmdb_type)
    |> where([u, _p], u.state in ^terminal_failure)
    |> select([u, _p], {u.season_number, u.episode_number, u.tried_release_guids})
    |> MediaCentaur.Repo.all()
    |> Enum.reduce(%{}, fn {season, episode, guids}, acc ->
      Map.update(acc, {season, episode}, guids || [], &Enum.uniq(&1 ++ (guids || [])))
    end)
  end

  defp bounds(item, settings) do
    {
      AutoGrabSettings.effective_min_quality(item.min_quality, settings),
      AutoGrabSettings.effective_max_quality(item.max_quality, settings)
    }
  end

  # The Q4 patience elevation: inside the window the unit demands the
  # ceiling (`min := max`); nil means inherit the plan criteria. Only
  # meaningful when there is headroom to be patient for.
  defp floor_for(want, patience, min_quality, max_quality, now) do
    if Quality.label_rank(max_quality) > Quality.label_rank(min_quality) and
         WantSchedule.floor_elevated?(want, patience, now) do
      max_quality
    end
  end

  defp unit_label(%{season_number: season, episode_number: episode, title: nil}) do
    "S#{pad(season)}E#{pad(episode)}"
  end

  defp unit_label(%{season_number: season, episode_number: episode, title: title}) do
    "S#{pad(season)}E#{pad(episode)} · #{title}"
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
