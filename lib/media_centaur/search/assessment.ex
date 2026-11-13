defmodule MediaCentaur.Search.Assessment do
  @moduledoc """
  Whether a candidate release may fill a wanted unit: the gates it
  fails, in gate order. No failed gate means it is accepted.

  | Gate | Reason | Rejects |
  |---|---|---|
  | bait | `:red_flag` | a name or size `ReleaseRedFlags` flags |
  | exclusion | `:excluded` | a guid the caller has ruled out (tried, or refused by the user) |
  | identity | `:identity` | a release that is not the title, or not the wanted part of it |
  | date | `:published_early` | a release posted before the criteria's `available_from` |
  | quality | `:quality` | a quality outside the caller's bounds |

  Every gate is evaluated, so `reasons` lists all that failed and
  `reason/1` is the first — the one a run stops at. A caller that shows
  flagged releases instead of hiding them reads past a reason with
  `accepted?/2`.

  ## Scope

  The identity gate depends on how much of a TV release's scope the
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

  A movie has one scope, so it is judged the same under each. An
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

  @type reason :: :red_flag | :excluded | :identity | :published_early | :quality
  @type scope_rule :: :exact | :covering | :any | :run

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
  defp scope(:no_match), do: nil

  defp identity(result, %Criteria{type: :tmdb, tmdb_type: :tv} = criteria, :any),
    do: TitleMatcher.coverage(result, criteria)

  defp identity(result, %Criteria{type: :tmdb, tmdb_type: :tv} = criteria, :covering),
    do: TitleMatcher.covering(result, criteria)

  defp identity(result, %Criteria{type: :tmdb, tmdb_type: :tv, run: run} = criteria, :run)
       when is_map(run) do
    case CourCoverage.classify(result.title, criteria.title, run) do
      :no_match -> :no_match
      scope -> {:ok, scope}
    end
  end

  defp identity(result, %Criteria{tmdb_type: tmdb_type} = criteria, _scope_rule) do
    cond do
      not TitleMatcher.matches?(result, criteria) -> :no_match
      tmdb_type == :movie -> {:ok, :movie}
      true -> {:ok, nil}
    end
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
