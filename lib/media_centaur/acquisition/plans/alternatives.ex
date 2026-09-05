defmodule MediaCentaur.Acquisition.Plans.Alternatives do
  @moduledoc """
  The swap picker (UIDR-014 follow-up) and the gap banner's evidence
  (UIDR-022): what else the search corpus holds for a plan unit, why
  the run rejected what it rejected, and the user's deliberate choice
  of one of those candidates. Reads the corpus, never the indexer,
  except `search/1`, which fills the corpus first.
  """

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.CoverageGuard
  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.{LadderTerms, Plan, PlanUnit}
  alias MediaCentaur.Acquisition.ViewModels.{GapEvidence, PlanBoard}
  alias MediaCentaur.Repo
  alias MediaCentaur.Search.{Criteria, Quality, ReleaseCoverage, ReleaseRedFlags, TitleMatcher}

  @doc """
  The choosable alternatives for one plan unit — corpus candidates
  across the unit's ladder terms (zero indexer traffic), identity-
  verified, covering the unit, minus exclusions and the current
  assignment. Suspicious (bait-pattern) titles are **flagged, not
  hidden** — never auto-picked, but a deliberate human may choose one.
  Sorted: clean before suspicious, then quality, then source ladder
  (ADR-061), then seeders.
  """
  @spec for_unit(Ecto.UUID.t()) ::
          {:ok, [PlanBoard.Alternative.t()]} | {:error, :not_found}
  def for_unit(plan_unit_id) do
    with {:ok, unit} <- Plans.fetch_unit(plan_unit_id),
         {:ok, plan} <- Plans.fetch(unit.plan_id) do
      excluded = MapSet.new(unit.excluded_release_guids)
      size_preference = AutoGrabSettings.load().size_preference

      alternatives =
        plan
        |> unit_candidates(unit)
        |> Enum.reject(fn {result, _scope} ->
          result.guid == unit.assigned_guid or MapSet.member?(excluded, result.guid)
        end)
        |> Enum.map(fn {result, scope} ->
          %PlanBoard.Alternative{
            guid: result.guid,
            title: result.title,
            scope_label: scope_display(scope),
            quality: Quality.display_label(result.title),
            seeders: result.seeders,
            size_bytes: result.size_bytes,
            suspicious?: ReleaseRedFlags.suspicious?(result.title, result.size_bytes)
          }
        end)
        |> Enum.sort_by(
          &{&1.suspicious?, -quality_rank(&1.quality),
           -Quality.source_rank(Quality.source(&1.title), size_preference), -(&1.seeders || 0)}
        )
        |> Enum.take(12)

      {:ok, alternatives}
    end
  end

  @doc """
  The swap picker's "find more" action: live-fills the corpus for the
  unit's ladder terms (consult-first — fresh terms cost nothing; terms
  the descent never reached go to the indexer), then returns the
  refreshed alternatives. Individual search failures are skipped, not
  raised — the picker shows whatever the corpus knows. Blocking and
  potentially slow (live indexer fan-out per stale term) — UI callers
  run it via `start_async`.
  """
  @spec search(Ecto.UUID.t()) ::
          {:ok, [PlanBoard.Alternative.t()]} | {:error, :not_found}
  def search(plan_unit_id) do
    with {:ok, unit} <- Plans.fetch_unit(plan_unit_id),
         {:ok, plan} <- Plans.fetch(unit.plan_id) do
      plan
      |> LadderTerms.for_unit(unit)
      |> Enum.each(&Corpus.search/1)

      for_unit(plan_unit_id)
    end
  end

  @doc """
  The durable evidence behind the board's gap banner (UIDR-022),
  derived from the search corpus — never the transient activity
  ticker, so a re-opened board reads the same days later. Movie plans
  get per-candidate rejection reasons in the run's gate order
  (red-flag, exclusion, identity); TV plans stay aggregate. Ladder
  terms without a corpus record (never searched, search failed, or
  pruned past retention) are absent from `searches`.
  """
  @spec gap_evidence(Plan.t()) :: GapEvidence.t()
  def gap_evidence(%Plan{} = plan) do
    gap_units =
      plan.id
      |> Plans.units_for()
      |> Enum.filter(&(&1.status == "unfound"))

    terms = evidence_terms(plan, gap_units)

    searches =
      for term <- terms,
          record = Corpus.record_for(term, []),
          record != nil do
        %GapEvidence.Search{
          term: term,
          searched_at: record.searched_at,
          result_count: record.result_count
        }
      end

    raw =
      terms
      |> Enum.flat_map(&Corpus.candidates_for/1)
      |> Enum.uniq_by(& &1.guid)

    %GapEvidence{
      searches: searches,
      rejected: rejected_candidates(plan, gap_units, raw),
      raw_total: length(raw),
      checked_at: searches |> Enum.map(& &1.searched_at) |> Enum.max(DateTime, fn -> nil end)
    }
  end

  defp evidence_terms(%Plan{tmdb_type: "movie"} = plan, _gap_units), do: LadderTerms.for_plan(plan, [])

  defp evidence_terms(%Plan{tmdb_type: "tv"} = plan, gap_units) do
    LadderTerms.for_plan(plan, Enum.map(gap_units, &{&1.season_number, &1.episode_number}))
  end

  # Movie-only classification (TV recourse is deferred — UIDR-022): each
  # raw candidate carries the FIRST gate it fails, mirroring the run's
  # order. A candidate failing no gate is identity-matched below the
  # floor — the below-floor banner's territory, never listed here.
  defp rejected_candidates(%Plan{tmdb_type: "tv"}, _gap_units, _raw), do: []

  defp rejected_candidates(%Plan{tmdb_type: "movie"} = plan, gap_units, raw) do
    excluded = gap_units |> Enum.flat_map(& &1.excluded_release_guids) |> MapSet.new()
    criteria = %Criteria{type: :tmdb, title: plan.title, tmdb_type: :movie, year: plan.year}

    for result <- raw,
        reason = rejection_reason(result, excluded, criteria),
        reason != nil do
      %GapEvidence.Rejected{
        guid: result.guid,
        title: result.title,
        reason: reason,
        quality: Quality.display_label(result.title),
        seeders: result.seeders,
        size_bytes: result.size_bytes
      }
    end
  end

  defp rejection_reason(result, excluded, criteria) do
    cond do
      ReleaseRedFlags.suspicious?(result.title, result.size_bytes) -> :red_flag
      MapSet.member?(excluded, result.guid) -> :excluded
      not TitleMatcher.matches?(result, criteria) -> :identity
      true -> nil
    end
  end

  @doc """
  Deliberately assigns a corpus candidate the run rejected (UIDR-022) —
  the user's override for a matcher false-negative. Identity
  verification is intentionally skipped, and neither a red flag nor an
  earlier exclusion bars the pick: choosing from the rejected list IS
  the deliberate call. Movie plans only; only `ready` plans accept it.
  """
  @spec choose_rejected(Ecto.UUID.t(), String.t()) :: {:ok, Plan.t()} | {:error, term()}
  def choose_rejected(plan_unit_id, guid) when is_binary(guid) do
    with {:ok, unit} <- Plans.fetch_unit(plan_unit_id),
         {:ok, %Plan{} = plan} <- Plans.fetch(unit.plan_id),
         :ok <- rejected_choosable(plan) do
      case find_raw_candidate(plan, unit, guid) do
        nil ->
          {:error, :alternative_unavailable}

        {result, term} ->
          {:ok, _} =
            Repo.update(
              PlanUnit.assign_changeset(unit, %{
                assigned_guid: result.guid,
                assigned_title: result.title,
                assigned_term: term,
                assigned_quality: Quality.display_label(result.title),
                assigned_seeders: result.seeders,
                assigned_indexer_id: result.indexer_id,
                assigned_size_bytes: result.size_bytes,
                assigned_scope: nil
              })
            )

          Plans.broadcast_changed(plan)
          {:ok, plan}
      end
    end
  end

  defp rejected_choosable(%Plan{tmdb_type: "tv"}), do: {:error, :movie_only}
  defp rejected_choosable(%Plan{status: "ready"}), do: :ok
  defp rejected_choosable(%Plan{}), do: {:error, :not_ready}

  defp find_raw_candidate(plan, unit, guid) do
    plan
    |> LadderTerms.for_unit(unit)
    |> Enum.find_value(fn term ->
      term
      |> Corpus.candidates_for()
      |> Enum.find(&(&1.guid == guid))
      |> case do
        nil -> nil
        result -> {result, term}
      end
    end)
  end

  @doc """
  Deliberately assigns a corpus candidate to a unit (the swap picker's
  choice). The candidate claims **every** non-excluded plan unit its
  scope covers — accounting stays per-unit total — and the plan
  broadcasts. Only `ready` plans accept choices.
  """
  @spec choose_release(Ecto.UUID.t(), String.t()) :: {:ok, Plan.t()} | {:error, term()}
  def choose_release(plan_unit_id, guid) when is_binary(guid) do
    with {:ok, unit} <- Plans.fetch_unit(plan_unit_id),
         {:ok, %Plan{status: "ready"} = plan} <- Plans.fetch(unit.plan_id),
         {:ok, {result, scope, term}} <- find_candidate(plan, unit, guid) do
      covered_units =
        plan.id
        |> Plans.units_for()
        |> Enum.filter(fn candidate_unit ->
          candidate_unit.status != "excluded" and
            covers_unit?(plan, scope, candidate_unit, unit, result.publish_date)
        end)

      attrs = %{
        assigned_guid: result.guid,
        assigned_title: result.title,
        assigned_term: term,
        assigned_quality: Quality.display_label(result.title),
        assigned_seeders: result.seeders,
        assigned_indexer_id: result.indexer_id,
        assigned_size_bytes: result.size_bytes,
        assigned_scope: scope_display(scope)
      }

      {:ok, _} =
        Repo.transaction(fn ->
          Enum.each(covered_units, fn covered ->
            {:ok, _} = Repo.update(PlanUnit.assign_changeset(covered, attrs))
          end)
        end)

      Plans.broadcast_changed(plan)
      {:ok, plan}
    else
      {:ok, %Plan{}} -> {:error, :not_ready}
      error -> error
    end
  end

  # All identity-verified corpus candidates that can cover this unit,
  # as {result, scope} pairs (movies carry the :movie pseudo-scope).
  defp unit_candidates(plan, unit) do
    plan
    |> LadderTerms.for_unit(unit)
    |> Enum.flat_map(fn term ->
      term
      |> Corpus.candidates_for()
      |> Enum.map(&{term, &1})
    end)
    |> Enum.uniq_by(fn {_term, result} -> result.guid end)
    |> Enum.flat_map(fn {term, result} ->
      case verify(plan, unit, result) do
        {:ok, scope} -> [{result, scope, term}]
        :no_match -> []
      end
    end)
    |> Enum.map(fn {result, scope, _term} -> {result, scope} end)
  end

  defp find_candidate(plan, unit, guid) do
    plan
    |> LadderTerms.for_unit(unit)
    |> Enum.find_value({:error, :alternative_unavailable}, fn term ->
      candidate =
        term
        |> Corpus.candidates_for()
        |> Enum.find(&(&1.guid == guid))

      with %{} <- candidate,
           {:ok, scope} <- verify(plan, unit, candidate) do
        {:ok, {candidate, scope, term}}
      else
        _ -> nil
      end
    end)
  end

  defp verify(%Plan{tmdb_type: "movie"} = plan, _unit, result) do
    criteria = %Criteria{type: :tmdb, title: plan.title, tmdb_type: :movie, year: plan.year}
    if TitleMatcher.matches?(result, criteria), do: {:ok, :movie}, else: :no_match
  end

  defp verify(%Plan{tmdb_type: "tv"} = plan, unit, result) do
    criteria = %Criteria{
      type: :tmdb,
      title: plan.title,
      tmdb_type: :tv,
      origin_country: plan.origin_country || []
    }

    with {:ok, scope} <- TitleMatcher.coverage(result, criteria),
         true <- ReleaseCoverage.covers?(scope, unit.season_number, unit.episode_number),
         true <- CoverageGuard.can_contain?(result.publish_date, unit.air_date) do
      {:ok, scope}
    else
      _ -> :no_match
    end
  end

  defp covers_unit?(%Plan{tmdb_type: "movie"}, :movie, candidate_unit, chosen_unit, _publish_date),
    do: candidate_unit.id == chosen_unit.id

  defp covers_unit?(_plan, scope, candidate_unit, _chosen_unit, publish_date) do
    ReleaseCoverage.covers?(scope, candidate_unit.season_number, candidate_unit.episode_number) and
      CoverageGuard.can_contain?(publish_date, candidate_unit.air_date)
  end

  defp scope_display(:movie), do: nil
  defp scope_display(scope), do: ReleaseCoverage.scope_label(scope)

  # Display-label ladder for picker sorting. Below-floor resolutions rank
  # between the tiers and "no signal", so a known-720p rip never sorts
  # under a resolution-less title on source strength alone (ADR-061).
  defp quality_rank("4K"), do: 5
  defp quality_rank("1080p"), do: 4
  defp quality_rank("720p"), do: 3
  defp quality_rank("576p"), do: 2
  defp quality_rank("480p"), do: 1
  defp quality_rank("DVD"), do: 1
  defp quality_rank(_quality), do: 0
end
