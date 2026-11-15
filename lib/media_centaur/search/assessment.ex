defmodule MediaCentaur.Search.Assessment do
  @moduledoc """
  Whether a candidate release may fill a wanted unit: the gates it
  fails, in gate order. No failed gate means it is accepted.

  | Gate | Reason | Rejects |
  |---|---|---|
  | bait | `:red_flag` | a name or size `ReleaseRedFlags` flags |
  | exclusion | `:excluded` | a guid the caller has ruled out (tried, or refused by the user) |
  | identity | `:identity` | a release that is not the title |
  | coverage | `:coverage` | a release of the title that does not contain the wanted part of it |
  | date | `:published_early` | a release posted before the criteria's `available_from` |
  | quality | `:quality` | a quality outside the caller's bounds |

  Every gate is evaluated, so `reasons` lists all that failed and
  `reason/1` is the first — the one a run stops at. A caller that shows
  flagged releases instead of hiding them reads past a reason with
  `accepted?/2`.

  ## Scope

  The coverage gate depends on how much of a TV release's scope the
  caller will take (`:scope`):

    * `:exact` — the unit and nothing wider (`TitleMatcher.matches?/2`).
      What an automatic grab uses: an episode never silently becomes a
      season pack.
    * `:covering` — any release containing the unit
      (`TitleMatcher.covering/2`). What a person choosing is offered.
    * `:any` — any scope of the show (`TitleMatcher.coverage/2`). What
      the planner gathers; it decides which scopes to use.
    * `:run` — a release named for the criteria's later broadcast run
      (`CourCoverage.classify/3`).

  A release of the show that the rule turns away fails the coverage
  gate; a release that is not the show at all (`TitleMatcher.coverage/2`
  finds no scope of it) fails the identity gate. A movie has one scope,
  so it is judged the same under each and never fails coverage. An
  accepted assessment carries the release's `scope`: `:movie`, the
  coverage scope, or `nil` under `:exact` for TV.

  Pure module — no I/O, no DB.
  """

  alias MediaCentaur.Search.{
    CourCoverage,
    Criteria,
    Quality,
    ReleaseCoverage,
    ReleaseRedFlags,
    SearchResult,
    TitleMatcher
  }

  @type reason :: :red_flag | :excluded | :identity | :coverage | :published_early | :quality
  @type scope_rule :: :exact | :covering | :any | :run

  @reasons [:red_flag, :excluded, :identity, :coverage, :published_early, :quality]

  @doc "Every reason, in gate order."
  @spec reasons() :: [reason()]
  def reasons, do: @reasons

  @enforce_keys [:reasons]
  defstruct [:scope, reasons: []]

  @type t :: %__MODULE__{scope: :movie | ReleaseCoverage.t() | nil, reasons: [reason()]}

  @doc """
  Judges `result` against `criteria`.

  Options:

    * `:excluded` — a `MapSet` of guids ruled out. Default: none.
    * `:scope` — see the module doc. Default `:exact`.
    * `:quality` — `{min, max}` storage labels (`Quality.acceptable?/3`).
      Default: no quality gate.
  """
  @spec assess(SearchResult.t(), Criteria.t(), keyword()) :: t()
  def assess(%SearchResult{} = result, %Criteria{} = criteria, opts \\ []) do
    excluded = Keyword.get(opts, :excluded, MapSet.new())
    identity = identity(result, criteria, Keyword.get(opts, :scope, :exact))

    reasons =
      [
        red_flag: ReleaseRedFlags.suspicious?(result.title, result.size_bytes),
        excluded: MapSet.member?(excluded, result.guid),
        identity: identity == :no_match,
        coverage: identity == :other_part,
        published_early: published_early?(result, criteria),
        quality: outside_bounds?(result, Keyword.get(opts, :quality))
      ]
      |> Enum.filter(fn {_reason, failed?} -> failed? end)
      |> Keyword.keys()

    %__MODULE__{reasons: reasons, scope: scope(identity)}
  end

  @doc "Whether no gate failed, reading past any reason in `ignoring:`."
  @spec accepted?(t(), keyword()) :: boolean()
  def accepted?(%__MODULE__{reasons: reasons}, opts \\ []),
    do: reasons -- Keyword.get(opts, :ignoring, []) == []

  @doc "The first gate that failed, or `nil` for an accepted release."
  @spec reason(t()) :: reason() | nil
  def reason(%__MODULE__{reasons: reasons}), do: List.first(reasons)

  defp scope({:ok, scope}), do: scope
  defp scope(_rejected), do: nil

  # `{:ok, scope}` for a release the rule takes, `:other_part` for a
  # release of the show the rule turns away, `:no_match` for anything
  # else.
  defp identity(result, %Criteria{type: :tmdb, tmdb_type: :tv} = criteria, scope_rule) do
    with :no_match <- within_rule(result, criteria, scope_rule),
         {:ok, _other_scope} <- TitleMatcher.coverage(result, criteria) do
      :other_part
    end
  end

  defp identity(result, %Criteria{} = criteria, _scope_rule) do
    if TitleMatcher.matches?(result, criteria), do: {:ok, :movie}, else: :no_match
  end

  defp within_rule(result, criteria, :any), do: TitleMatcher.coverage(result, criteria)
  defp within_rule(result, criteria, :covering), do: TitleMatcher.covering(result, criteria)

  defp within_rule(result, %Criteria{run: run} = criteria, :run) when is_map(run) do
    case CourCoverage.classify(result.title, criteria.title, run) do
      :no_match -> :no_match
      scope -> {:ok, scope}
    end
  end

  defp within_rule(result, criteria, _exact) do
    if TitleMatcher.matches?(result, criteria), do: {:ok, nil}, else: :no_match
  end

  # Unknown on either side never rejects: nothing is refused on a date
  # nobody has.
  defp published_early?(%SearchResult{publish_date: publish_date}, %Criteria{
         available_from: available_from
       }) do
    case {SearchResult.published_on(publish_date), available_from} do
      {%Date{} = published, %Date{} = available} -> Date.before?(published, available)
      _unknown -> false
    end
  end

  defp outside_bounds?(_result, nil), do: false
  defp outside_bounds?(result, {min, max}), do: not Quality.acceptable?(result.quality, min, max)
end
