defmodule MediaCentaur.Acquisition.Planner do
  @moduledoc """
  The coverage optimizer (media-search campaign Phase 3): maps wanted
  units to release candidates, applying the objective hierarchy

      Coverage → Consolidation → User preference → Health

  and the automatic granularity ladder (complete series → season range
  → season pack → episode span → single episode). The user picks
  *what* they want; this module picks *how*.

  ## Fit gating — never grab a pack you mostly don't want

  Broad-first consolidation is right when you want *most* of a span and
  wrong when you want a sparse slice of it: a single wanted episode
  "covered" by a complete-series pack would otherwise drag the whole
  series down. The gate is **fit** — `wanted-in-span / span-total` (the
  span's total aired-episode count) — measured against `pack_min_fit`.
  A pack scope only stays a candidate when its fit clears the
  threshold; below it, the pack is set aside as an *offer* (surfaced to
  the user with the over-grab spelled out, never auto-assigned).

  Gating is opt-in and monotonic: it activates only when `prefs` carry
  a numeric `pack_min_fit`, and a pack is gated out only when its
  span-total is *known* (from `prefs.span_sizes`) and the fit falls
  short. Unknown span-total → no gate (legacy broad-first). So a caller
  with span sizes (media search) gets fit-aware planning; a caller
  without (movies, legacy) is unchanged. Episode spans need no span
  sizes — their breadth is intrinsic (`last - first + 1`). Fit is
  judged against `prefs.all_wanted` (the full plan want) so a season's
  density reads the same across quality-floor groups.

  ## Algorithm

  Acceptability-filter the options (quality bounds — best-available-now
  has **no** patience window), fit-gate the packs, then consolidate
  broad-first over what survives: every multi-unit option still
  covering two or more remaining wanted units claims them, in
  `{breadth, quality, source, seeders}` order — so the widest acceptable
  consolidation wins its span, a 4K pack outranks a 1080p pack, the
  source ladder (ADR-061, `prefs.size_preference`) breaks resolution
  ties, and seeders break ties between equals. Remaining units get
  their per-unit best (quality, source, then seeders); units nothing
  acceptable covers come
  back as `unfound` — search results, never pursuit leaves (campaign
  hard boundary) — each carrying its best fit-gated `offer`, if any.

  **Within a span, consolidation outranks per-unit quality** (campaign
  plan-solver-consolidation, 2026-06-10 — supersedes the original
  summed-quality ensemble comparison): an acceptable pack is never
  fragmented into singles for a quality upgrade, because every claimed
  unit's higher-quality alternatives stay one click away in the plan
  board's swap picker, while overlapping grabs are unconditionally
  duplicate data. The retired comparison let one 4K single veto a
  whole season pack and then re-grab the pack anyway for the leftovers
  (7 grabs where 2 sufficed).

  Pure module — no I/O, no DB. Inputs are pre-verified: the plan runner
  is responsible for show-identity (`TitleMatcher.coverage/2`) and for
  filtering excluded releases before solving.
  """

  alias MediaCentaur.Search.{Quality, ReleaseCoverage, SearchResult}

  defmodule Option do
    @moduledoc """
    One identity-verified candidate: the release, its classified coverage
    scope, and an optional `coverable` cap.

    `coverable` is a `MapSet` of the `{season, episode}` units the release
    can *physically* contain — the cour-aware coverage guard. The plan
    runner computes it (units that aired on or before the release was
    published) and the planner intersects it with the scope wherever it
    credits the option, so a first-run pack is never assigned episodes it
    was encoded before. `:all` (the default) means "no cap" — the scope
    alone decides, the legacy behaviour for every date-blind caller.
    """

    @enforce_keys [:result, :scope]
    defstruct [:result, :scope, coverable: :all, offer_only: false]

    @type coverable :: :all | MapSet.t(ReleaseCoverage.unit())

    @type t :: %__MODULE__{
            result: SearchResult.t(),
            scope: ReleaseCoverage.t(),
            coverable: coverable(),
            offer_only: boolean()
          }
  end

  defmodule Assignment do
    @moduledoc "One chosen release and the wanted units it satisfies."

    @enforce_keys [:result, :scope, :units]
    defstruct [:result, :scope, :units]

    @type t :: %__MODULE__{
            result: SearchResult.t(),
            scope: ReleaseCoverage.t(),
            units: [ReleaseCoverage.unit()]
          }
  end

  defmodule Solution do
    @moduledoc """
    The solved plan: assignments, the units nothing acceptable covers,
    and the `offers` — a `unit => Option` map of the best fit-gated pack
    that *would* cover an unfound unit (over-grab the user can opt into).
    """

    @enforce_keys [:assignments, :unfound]
    defstruct [:assignments, :unfound, offers: %{}]

    @type t :: %__MODULE__{
            assignments: [Assignment.t()],
            unfound: [ReleaseCoverage.unit()],
            offers: %{ReleaseCoverage.unit() => Option.t()}
          }
  end

  @type prefs :: %{
          :min_quality => String.t(),
          :max_quality => String.t(),
          optional(:size_preference) => Quality.size_preference(),
          optional(:pack_min_fit) => number() | nil,
          optional(:span_sizes) => %{String.t() => pos_integer()},
          optional(:all_wanted) => [ReleaseCoverage.unit()]
        }

  @spec solve([ReleaseCoverage.unit()], [Option.t()], prefs()) :: Solution.t()
  def solve(wanted, options, prefs) when is_list(wanted) and is_list(options) do
    acceptable =
      Enum.filter(options, fn %Option{result: result} ->
        Quality.acceptable?(result.quality, prefs.min_quality, prefs.max_quality)
      end)

    # Offer-only options (cour candidates — fuzzy naming, never
    # auto-grabbed) bypass assignment entirely: they go straight to the
    # offers bucket regardless of fit, so the user confirms on the board.
    {forced_offers, gradable} = Enum.split_with(acceptable, & &1.offer_only)

    all_wanted = Map.get(prefs, :all_wanted) || wanted
    {eligible, gated} = partition_by_fit(gradable, all_wanted, prefs)
    gated = gated ++ forced_offers

    size_preference = Map.get(prefs, :size_preference, "fidelity")

    {assignments, remaining} = consolidate(wanted, eligible, size_preference)
    {single_assignments, unfound} = assign_singles(remaining, eligible, size_preference)

    %Solution{
      assignments: assignments ++ single_assignments,
      unfound: unfound,
      offers: offers_for(unfound, gated, size_preference)
    }
  end

  # ---------------------------------------------------------------------------
  # Consolidation pass — broad scopes first. Any option still covering
  # two or more remaining wanted units claims them; the sort order
  # (breadth, then quality, then seeders) IS the policy, so the better
  # pack is judged — and claims — first. No per-unit ensemble
  # comparison: fragmenting a span for quality is never automatic (see
  # moduledoc), and an option whose span has real holes only ever
  # claims what it covers — singles fill the rest in the next pass.
  # ---------------------------------------------------------------------------

  defp consolidate(wanted, options, size_preference) do
    options
    |> Enum.filter(&multi_unit?(&1, wanted))
    |> Enum.sort_by(
      &{-breadth(&1.scope), -quality_rank(&1), -source_rank(&1, size_preference), -seeders(&1)}
    )
    |> Enum.reduce({[], wanted}, fn option, {assignments, remaining} ->
      covered = option_covered_units(option, remaining)

      if length(covered) > 1 do
        assignment = %Assignment{result: option.result, scope: option.scope, units: covered}
        {[assignment | assignments], remaining -- covered}
      else
        {assignments, remaining}
      end
    end)
    |> then(fn {assignments, remaining} -> {Enum.reverse(assignments), remaining} end)
  end

  defp multi_unit?(%Option{} = option, wanted) do
    option |> option_covered_units(wanted) |> length() > 1
  end

  # The wanted units this option actually credits — its scope's coverage,
  # capped by the `coverable` allow-list (the coverage guard). `:all`
  # means the scope alone decides.
  defp option_covered_units(%Option{} = option, wanted) do
    Enum.filter(wanted, fn {season, episode} -> option_covers?(option, season, episode) end)
  end

  defp option_covers?(%Option{scope: scope, coverable: :all}, season, episode) do
    ReleaseCoverage.covers?(scope, season, episode)
  end

  defp option_covers?(%Option{scope: scope, coverable: coverable}, season, episode) do
    ReleaseCoverage.covers?(scope, season, episode) and
      MapSet.member?(coverable, {season, episode})
  end

  # ---------------------------------------------------------------------------
  # Singles pass — best remaining provider per unit.
  # ---------------------------------------------------------------------------

  defp assign_singles(remaining, options, size_preference) do
    {by_option, unfound} =
      Enum.reduce(remaining, {%{}, []}, fn {season, episode} = unit, {by_option, unfound} ->
        provider =
          options
          |> Enum.filter(&option_covers?(&1, season, episode))
          |> Enum.max_by(
            &{quality_rank(&1), source_rank(&1, size_preference), seeders(&1)},
            fn -> nil end
          )

        case provider do
          nil -> {by_option, [unit | unfound]}
          option -> {Map.update(by_option, option, [unit], &[unit | &1]), unfound}
        end
      end)

    assignments =
      Enum.map(by_option, fn {option, units} ->
        %Assignment{result: option.result, scope: option.scope, units: Enum.reverse(units)}
      end)

    {assignments, Enum.reverse(unfound)}
  end

  # ---------------------------------------------------------------------------
  # Fit gating — packs whose span is mostly unwanted are set aside as
  # offers, not assigned. Gating is off unless `pack_min_fit` is numeric;
  # a pack is gated only when its span-total is known and the fit falls
  # short, so unknown spans (and every single episode) always survive.
  # ---------------------------------------------------------------------------

  defp partition_by_fit(options, all_wanted, %{pack_min_fit: threshold} = prefs)
       when is_number(threshold) do
    span_sizes = Map.get(prefs, :span_sizes, %{})

    Enum.split_with(options, fn %Option{} = option ->
      fit_ok?(option, all_wanted, span_sizes, threshold)
    end)
  end

  defp partition_by_fit(options, _all_wanted, _prefs), do: {options, []}

  defp fit_ok?(%Option{scope: scope} = option, wanted, span_sizes, threshold) do
    case span_total(scope, span_sizes) do
      nil ->
        true

      total when total > 0 ->
        length(option_covered_units(option, wanted)) / total >= threshold

      _zero_or_negative ->
        true
    end
  end

  # The realistic episode count a grab of this scope lands on disk — the
  # fit denominator. `nil` means "can't tell" (no span sizes for a
  # season/series), which the gate reads as "don't judge".
  defp span_total({:episode, _season, _episode}, _span_sizes), do: 1
  defp span_total({:episodes, _season, first, last}, _span_sizes), do: last - first + 1
  defp span_total({:season, season}, span_sizes), do: season_size(span_sizes, season)

  defp span_total({:seasons, first, last}, span_sizes) do
    sizes = Enum.map(first..last, &season_size(span_sizes, &1))
    if Enum.all?(sizes, &is_integer/1), do: Enum.sum(sizes)
  end

  defp span_total(:series, span_sizes) do
    sizes = Map.values(span_sizes)
    if sizes != [], do: Enum.sum(sizes)
  end

  defp span_total(:unknown, _span_sizes), do: nil

  defp season_size(span_sizes, season), do: Map.get(span_sizes, Integer.to_string(season))

  # Best fit-gated pack per unfound unit: narrowest scope first (least
  # over-grab), then quality, then source, then seeders.
  defp offers_for(unfound, gated, size_preference) do
    for {season, episode} = unit <- unfound,
        covering =
          gated
          |> Enum.filter(&option_covers?(&1, season, episode))
          |> Enum.sort_by(
            &{breadth(&1.scope), -quality_rank(&1), -source_rank(&1, size_preference), -seeders(&1)}
          ),
        [best | _] <- [covering],
        into: %{},
        do: {unit, best}
  end

  # ---------------------------------------------------------------------------

  defp breadth(:series), do: 4
  defp breadth({:seasons, _first, _last}), do: 3
  defp breadth({:season, _season}), do: 2
  defp breadth({:episodes, _season, _first, _last}), do: 1
  defp breadth({:episode, _season, _episode}), do: 0

  defp quality_rank(%Option{result: %SearchResult{quality: quality}}), do: Quality.rank(quality)

  defp source_rank(%Option{result: %SearchResult{title: title}}, size_preference) do
    Quality.source_rank(Quality.source(title), size_preference)
  end

  defp seeders(%Option{result: %SearchResult{seeders: seeders}}), do: seeders || 0
end
