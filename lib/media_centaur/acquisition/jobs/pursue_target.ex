defmodule MediaCentaur.Acquisition.Jobs.PursueTarget do
  @moduledoc """
  Oban worker that searches Prowlarr for a pursuit's recipe and either
  acquires the best matching release (TMDB recipe) or surfaces results
  to the user via the decision card (Prowlarr-query recipe).

  ## Recipe-polymorphic outcomes

  - **TMDB recipe** — Prowlarr results are TitleMatcher-filtered and
    Quality-bounded. Best acceptable hit transitions the target
    `seeking → acquired` and submits to the download client. No
    acceptable result snoozes the worker (exponential backoff) until
    the configured attempt cap is hit, at which point the target moves
    to `failed` and the pursuit to `exhausted`.
  - **Prowlarr-query recipe** — TitleMatcher is skipped (the user
    typed the query they trust). Any non-empty Prowlarr result set
    sets the pursuit's `awaiting_decision_at` flag so the user picks
    from the decision card. Empty results snooze and retry on the
    same schedule as TMDB.

  ## Quality

  Releases below the pursuit's `min_quality` are filtered out (TMDB
  recipe only). Among acceptable results 4K is preferred over 1080p
  (`Quality.rank/1`). Quality bounds live on the pursuit (in the
  `criteria` map).

  ## Lifecycle and snooze

      seeking ─► (acceptable TMDB result)         ─► acquired
              ─► (any Prowlarr-query result)      ─► (pursuit awaiting decision)
              ─► (no acceptable result)           ─► snoozed via Oban (exp. backoff)
              ─► (max attempts, a pack has it)    ─► (pursuit awaiting decision)
              ─► (max attempts exceeded)          ─► failed
              ─► (Prowlarr not configured)       ─► snoozed 1h, NO request, NO bump
              ─► (integration known down)         ─► held, NO request, NO bump
              ─► (Prowlarr error mid-search)      ─► snoozed at the cadence, NO bump
              ─► (download client unreachable)    ─► snoozed at the cadence, NO bump

  ## Held work

  Before each metered request the worker asks
  `MediaCentaur.IntegrationAvailability` whether the integration it
  needs is up: `:prowlarr` before the search, `{:handoff, protocol}`
  before the grab. A known-down integration holds the work — no
  request, no attempt, no outcome stamp — and snoozes at
  `MediaCentaur.Search.ProbeJob.cadence_seconds/0`, so the pursuit
  resumes within a minute of recovery. An *unconfigured* Prowlarr is
  not an outage: nothing can change until Settings do, so that is a
  long snooze instead. The worker reads the two halves separately —
  rather than `IntegrationAvailability.available?/1`, which folds them
  together — precisely because they warrant different waits.

  Exponential backoff: `min(4 * 2^(attempt - 1), 24)` hours, capped at 24h.
  The attempt cap is `AutoGrabSettings.max_attempts` (Settings →
  Acquisition; default 12 — about a week at the cap), read on every
  attempt.

  ## Cancellation

  The worker reads its target row on every wake. Terminal-state
  targets cause an immediate `:ok` early-exit with no Prowlarr call.
  This is how `Targets.cancel_target/2` cuts a snoozed job short
  — it flips the row, the next wake sees it.
  """
  use Oban.Worker, queue: :acquisition, unique: [period: 300, keys: [:target_id]]

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Acquisition.CancelReasons

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability

  alias MediaCentaur.Acquisition.{
    AutoGrabSettings,
    Corpus,
    Cours,
    InfoHash,
    Target,
    TargetEvents,
    TargetStatus
  }

  alias MediaCentaur.Search.{
    Criteria,
    ProbeJob,
    Prowlarr,
    Quality,
    QueryBuilder,
    ReleasePreference,
    ReleaseRedFlags,
    SearchResult,
    TitleMatcher
  }

  alias MediaCentaur.Acquisition.Pursuits.{Commands, Pursuit, Recipe, State, Unit, UnitState, Units}
  alias MediaCentaur.Repo

  @snooze_cap_hours 24
  @handoff_slots IntegrationAvailability.handoff_slots()
  # An unconfigured Prowlarr fails every request instantly; nothing to
  # do until Settings change. Not availability's business.
  @unconfigured_snooze_seconds 60 * 60
  @needs_decision_prompt "Pick a release."
  @pack_prompt "Only a pack has this episode. Picking it downloads the whole pack."

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"target_id" => target_id}}) do
    case load_target_with_pursuit(target_id) do
      {nil, _} ->
        {:ok, :not_found}

      {%Target{} = target, nil} ->
        Log.warning(:acquisition, "pursue_target: target #{target.id} has no pursuit; failing")
        {:ok, _failed} = Repo.update(Target.failed_changeset(target, CancelReasons.orphan_target()))
        {:ok, :no_pursuit}

      {%Target{} = target, %Pursuit{} = pursuit} ->
        dispatch(target, pursuit, covered_unit(target, pursuit))
    end
  end

  # Pursuit and unit state are checked before target status: the
  # aggregate is the authority. Never pursue on a terminal pursuit or a
  # terminal unit, even if the target row somehow survived as
  # `seeking`. Defense in depth — the terminal commands already cancel
  # in-flight targets, which the target-status guard below also
  # catches. This branch closes any remaining race window and any
  # future code path that creates a target on an already-closed goal.
  defp dispatch(%Target{} = target, %Pursuit{state: state} = pursuit, unit) do
    cond do
      State.terminal?(state) ->
        {:ok, :pursuit_terminal}

      match?(%Unit{}, unit) and UnitState.terminal?(unit.state) ->
        {:ok, :unit_terminal}

      TargetStatus.terminal?(target.status) ->
        {:ok, String.to_existing_atom(target.status)}

      true ->
        pursue(target, pursuit, unit)
    end
  end

  # One DB round-trip for both rows. Returns `{target_or_nil, pursuit_or_nil}`.
  defp load_target_with_pursuit(target_id) do
    query =
      from(t in Target,
        left_join: p in Pursuit,
        on: p.id == t.pursuit_id,
        where: t.id == ^target_id,
        select: {t, p}
      )

    case Repo.one(query) do
      nil -> {nil, nil}
      pair -> pair
    end
  end

  # The unit this target covers (exactly one until packs land —
  # ADR-055). Falls back to the pursuit's sole unit for legacy targets
  # without coverage rows.
  defp covered_unit(%Target{} = target, %Pursuit{} = pursuit) do
    case Units.covered_by(target.id) do
      [unit | _] -> unit
      [] -> Units.single!(pursuit.id)
    end
  end

  defp pursue(%Target{} = target, %Pursuit{} = pursuit, %Unit{} = unit) do
    cond do
      not Capabilities.prowlarr_ready?() ->
        Log.info(:acquisition, "acquisition waiting — #{target.title} (Prowlarr is not configured)")
        {:snooze, @unconfigured_snooze_seconds}

      not IntegrationAvailability.up?(:prowlarr) ->
        hold(target, :prowlarr)

      true ->
        search_and_act(target, pursuit, unit)
    end
  end

  # Held: no request, no attempt, no stamp. Ask again at the probe
  # cadence; a snooze is a database write, free.
  defp hold(%Target{} = target, integration) do
    Log.info(:acquisition, "acquisition held — #{target.title} (#{held_reason(integration)})")
    {:snooze, ProbeJob.cadence_seconds()}
  end

  # This line lands in the Status drill-in, so it reads as a sentence
  # rather than a term.
  defp held_reason(:prowlarr), do: "Prowlarr is down"

  defp held_reason({:handoff, slot}), do: "Prowlarr cannot reach the #{slot} download client"

  defp search_and_act(%Target{} = target, %Pursuit{} = pursuit, %Unit{} = unit) do
    Log.info(
      :acquisition,
      "acquisition search — #{target.title} (attempt #{target.attempt_count + 1})"
    )

    prefs = effective_prefs(pursuit)

    # Cour-aware: a unit in a later broadcast run searches run-shaped
    # queries (`Cours.with_run/2`), or a committed later-cour release
    # can't be re-found on retry.
    criteria =
      pursuit |> Recipe.for_unit(unit) |> Recipe.to_criteria() |> Cours.with_run(pursuit.tmdb_id)

    case search_until_match(unit, criteria, QueryBuilder.build(criteria), prefs) do
      {:ok, best} -> handle_found(target, pursuit, unit, criteria, best)
      {:needs_decision, _results} -> handle_needs_decision(target, pursuit, unit)
      {:no_match, outcome} -> handle_no_results(target, pursuit, unit, criteria, outcome)
      {:error, reason} -> handle_prowlarr_error(target, reason)
    end
  end

  # Quality bounds live on the pursuit's `criteria` map, read as-is; a
  # `min_quality` there is the title's lower-quality acceptance (ADR-063
  # §2). Nothing else sets one — there is no patience window (UIDR-041
  # §6).
  defp effective_prefs(%Pursuit{} = pursuit) do
    settings = AutoGrabSettings.load()
    criteria = pursuit.criteria || %{}

    %{
      min_quality: Map.get(criteria, "min_quality") || AutoGrabSettings.floor(),
      max_quality: Map.get(criteria, "max_quality") || settings.default_max_quality,
      size_preference: settings.size_preference
    }
  end

  @outcome_rank %{
    "no_results" => 0,
    "no_title_match" => 1,
    "no_acceptable_quality" => 2,
    "grab_failed" => 2
  }

  # Movie queries are alternate phrasings of ONE want; TV queries are a
  # narrowing sequence of scopes over a unit that is either covered or not. So movies
  # exhaust every query and keep the best, while TV still stops at the
  # first query that satisfies the unit. The two function names carry the
  # difference.
  defp search_until_match(unit, criteria, queries, prefs) do
    case {criteria.type, criteria.tmdb_type} do
      {:prowlarr_query, _tmdb_type} -> search_until_any_result(queries)
      {:tmdb, :movie} -> search_best_tmdb_match(unit, criteria, queries, prefs)
      {:tmdb, _tmdb_type} -> search_until_tmdb_match(unit, criteria, queries, prefs)
    end
  end

  # Searches go through the corpus (consult-first, ADR-055): a term
  # searched within the freshness window serves from durable knowledge
  # with zero indexer traffic — the snooze-retry loop is exactly the
  # automated caller the citizenship gate exists for.
  defp search_until_tmdb_match(unit, criteria, queries, prefs) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Corpus.search(query, opts) do
        {:ok, []} ->
          {:cont, acc}

        {:ok, results} ->
          case best_match(results, unit, criteria, prefs) do
            {:found, best} -> {:halt, {:ok, best}}
            {:none, outcome} -> {:cont, keep_more_informative(acc, outcome)}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  # A movie's queries are `Title year` then the bare `Title`: release
  # groups tag a film with whichever year their source used, so the year
  # query routinely matches a handful of releases while every better copy
  # sits behind the year-less one. Halting on the first query that hit let
  # the year decide the quality ceiling — and nobody clicks "Find more" on
  # an unattended retry loop, so the worse copy stuck permanently. Ties
  # keep the earlier query's candidate (`ReleasePreference.better_of/3`),
  # so the year-matched term still wins against an equal candidate from
  # the broader one.
  defp search_best_tmdb_match(unit, criteria, queries, prefs) do
    queries
    |> Enum.reduce_while({{:no_match, "no_results"}, nil}, fn {query, opts}, {outcome, best} ->
      case Corpus.search(query, opts) do
        {:ok, []} ->
          {:cont, {outcome, best}}

        {:ok, results} ->
          case best_match(results, unit, criteria, prefs) do
            {:found, candidate} ->
              {:cont, {outcome, ReleasePreference.better_of(best, candidate, prefs.size_preference)}}

            {:none, degraded} ->
              {:cont, {keep_more_informative(outcome, degraded), best}}
          end

        {:error, reason} ->
          {:halt, {{:error, reason}, best}}
      end
    end)
    |> case do
      {{:error, _reason} = error, _best} -> error
      {_outcome, %SearchResult{} = best} -> {:ok, best}
      {outcome, nil} -> outcome
    end
  end

  defp search_until_any_result(queries) do
    Enum.reduce_while(queries, {:no_match, "no_results"}, fn {query, opts}, acc ->
      case Corpus.search(query, opts) do
        {:ok, []} -> {:cont, acc}
        {:ok, results} -> {:halt, {:needs_decision, results}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp keep_more_informative({:no_match, current} = acc, candidate) do
    if rank(candidate) > rank(current), do: {:no_match, candidate}, else: acc
  end

  defp rank(outcome), do: Map.get(@outcome_rank, outcome, 0)

  # Single-pass classifier over Prowlarr results. Projects the pursuit's
  # `%Recipe{}` once (instead of once per result) and folds the prior
  # `reject |> filter |> filter |> sort_by` chain into one `reduce`. The
  # outcome distinction "no_title_match" vs "no_acceptable_quality" is
  # preserved by upgrading the outcome the first time we see a
  # title-matching but quality-unacceptable result. Exclusions come
  # from the unit's thread (ADR-055).
  defp best_match(results, unit, criteria, prefs) do
    excluded = MapSet.new(unit.tried_release_guids || [])

    results
    |> Enum.reduce({nil, "no_title_match"}, fn result, {best, outcome} = acc ->
      cond do
        ReleaseRedFlags.suspicious?(result.title, result.size_bytes) ->
          acc

        MapSet.member?(excluded, result.guid) ->
          acc

        is_nil(criteria) or not TitleMatcher.matches?(result, criteria) ->
          acc

        not Quality.acceptable?(result.quality, prefs.min_quality, prefs.max_quality) ->
          {best, "no_acceptable_quality"}

        true ->
          {ReleasePreference.better_of(best, result, prefs.size_preference), outcome}
      end
    end)
    |> case do
      {nil, outcome} -> {:none, outcome}
      {%SearchResult{} = result, _outcome} -> {:found, result}
    end
  end

  defp handle_found(target, pursuit, unit, criteria, %SearchResult{} = result) do
    if held_handoff?(result) do
      hold(target, {:handoff, result.protocol})
    else
      grab_found(target, pursuit, unit, criteria, result)
    end
  end

  # A result without a protocol cannot be attributed to a slot: grab,
  # and let the outcome be the evidence.
  defp held_handoff?(%SearchResult{protocol: protocol}) when protocol in @handoff_slots,
    do: not IntegrationAvailability.up?({:handoff, protocol})

  defp held_handoff?(%SearchResult{}), do: false

  defp grab_found(target, pursuit, unit, criteria, result) do
    case Prowlarr.grab(result) do
      :ok ->
        quality_label = Quality.label(result.quality)

        {:ok, updated} =
          Repo.update(
            Target.acquire_changeset(
              target,
              quality_label,
              result.title,
              result.guid,
              InfoHash.resolve(result)
            )
          )

        broadcast(%TargetEvents.Acquired{target: updated})
        Log.info(:acquisition, "acquisition acquired #{quality_label} — #{target.title}")
        {:ok, quality_label}

      {:error, reason} ->
        Log.warning(:acquisition, "acquisition grab failed — #{inspect(reason)}")

        if Prowlarr.grab_outage?(reason) do
          handle_infrastructure_failure(
            target,
            "download_client_unavailable",
            ProbeJob.cadence_seconds()
          )
        else
          handle_no_results(target, pursuit, unit, criteria, "grab_failed")
        end
    end
  end

  defp handle_needs_decision(target, pursuit, unit) do
    {:ok, _updated} = Repo.update(Target.attempt_changeset(target, "needs_decision"))

    case Commands.RequestDecision.execute(%{
           pursuit_id: pursuit.id,
           unit_id: unit.id,
           prompt: @needs_decision_prompt
         }) do
      {:ok, _pursuit} ->
        Log.info(
          :acquisition,
          "acquisition surfaced results — #{target.title} (Prowlarr query, awaiting pick)"
        )

        {:ok, :needs_decision}

      {:error, reason} ->
        Log.warning(:acquisition, "request_decision failed — #{inspect(reason)}")
        {:ok, :needs_decision_failed}
    end
  end

  defp handle_no_results(target, pursuit, unit, criteria, outcome) do
    {:ok, updated} =
      target
      |> Target.attempt_changeset(outcome)
      |> Repo.update()

    # The cap is the person's setting (Settings → Acquisition), read per
    # attempt so a change applies to pursuits already in flight.
    max_attempts = AutoGrabSettings.load().max_attempts

    cond do
      updated.attempt_count < max_attempts ->
        snooze(updated)

      pack_covers_unit?(unit, criteria) ->
        offer_pack(updated, pursuit, unit)

      true ->
        {:ok, failed} = Repo.update(Target.failed_changeset(updated, CancelReasons.exhausted()))
        broadcast(%TargetEvents.Failed{target: failed})
        Log.info(:acquisition, "acquisition exhausted — #{target.title} (#{max_attempts} attempts)")
        :ok
    end
  end

  # The attempt that would exhaust looks wider first: the episode term
  # has come up empty for a week, but a season or series pack the unit
  # never asked for may still contain it. Only a TV episode has anything
  # wider to look at; the corpus keeps this to one live search per term.
  defp pack_covers_unit?(unit, %Criteria{type: :tmdb, tmdb_type: :tv} = criteria) do
    excluded = MapSet.new(unit.tried_release_guids || [])

    criteria
    |> QueryBuilder.fallback()
    |> Enum.flat_map(fn {query, opts} ->
      case Corpus.search(query, opts) do
        {:ok, results} -> results
        {:error, _reason} -> []
      end
    end)
    |> Enum.uniq_by(& &1.guid)
    |> Enum.reject(&MapSet.member?(excluded, &1.guid))
    |> Enum.any?(&TitleMatcher.covers?(&1, criteria))
  end

  defp pack_covers_unit?(_unit, %Criteria{}), do: false

  # Asking beats exhausting: the decision card lists the pack, the
  # user decides whether the whole thing is worth the one episode.
  defp offer_pack(target, pursuit, unit) do
    {:ok, _updated} = Repo.update(Target.outcome_changeset(target, "pack_offered"))

    case Commands.RequestDecision.execute(%{
           pursuit_id: pursuit.id,
           unit_id: unit.id,
           prompt: @pack_prompt
         }) do
      {:ok, _pursuit} ->
        Log.info(:acquisition, "acquisition offers a pack — #{target.title} (awaiting pick)")
        {:ok, :needs_decision}

      {:error, reason} ->
        Log.warning(:acquisition, "request_decision failed — #{inspect(reason)}")
        {:ok, :needs_decision_failed}
    end
  end

  defp snooze(target) do
    seconds = snooze_seconds(target.attempt_count)
    {:ok, scheduled} = persist_next_attempt(target, seconds)
    broadcast(%TargetEvents.Snoozed{target: scheduled})

    Log.info(
      :acquisition,
      "acquisition snooze — #{target.title} (attempt #{scheduled.attempt_count})"
    )

    {:snooze, seconds}
  end

  defp handle_prowlarr_error(target, reason) do
    Log.warning(:acquisition, "acquisition prowlarr error — #{inspect(reason)}")
    handle_infrastructure_failure(target, "prowlarr_error", ProbeJob.cadence_seconds())
  end

  # The search or the grab could not reach the infrastructure — Prowlarr
  # itself, or the download client behind it. Recorded on the target for
  # the status line and snoozed without charging an attempt: the release
  # is fine, and the next attempt re-picks it from the corpus.
  defp handle_infrastructure_failure(target, outcome, snooze_seconds) do
    {:ok, updated} =
      target
      |> Target.outcome_changeset(outcome)
      |> Repo.update()

    {:ok, scheduled} = persist_next_attempt(updated, snooze_seconds)
    broadcast(%TargetEvents.Snoozed{target: scheduled})
    {:snooze, snooze_seconds}
  end

  # Denormalises Oban's `scheduled_at` onto the target row so the read
  # path (pursuit status, row rendering) can show "next attempt in
  # 2h 15m" without querying Oban.
  defp persist_next_attempt(target, seconds) do
    next_at = DateTime.add(DateTime.utc_now(), seconds, :second)

    target
    |> Target.schedule_next_attempt_changeset(next_at)
    |> Repo.update()
  end

  defp snooze_seconds(attempt_count) do
    hours = trunc(min(:math.pow(2, attempt_count - 1) * 4, @snooze_cap_hours))
    hours * 60 * 60
  end

  defp broadcast(message), do: Acquisition.broadcast_update(message)
end
