defmodule MediaCentaur.Acquisition.ViewModels.GapVerdict do
  @moduledoc """
  The gap banner's adaptive diagnosis (UIDR-022): renders a
  `GapEvidence` snapshot into the world the counts mechanically prove —
  never an inferred cause, never a bare "not available".

  Worlds, in precedence order:

  * `:blind` — the search couldn't ask anyone (UIDR-016; outranks
    everything, keeps that record's copy verbatim).
  * `:below_preference` — every remaining unit has releases, all below
    the quality preference (UIDR-029). Applies only when there are no
    bare gaps: a bare gap's diagnosis (below) outranks it. Never says
    "floor" — user copy calls it the quality preference.
  * `:no_evidence` — no ladder term has a corpus record (never
    searched, search failed, or pruned past retention).
  * `:rejected` — raw results exist, none qualified. Movie plans get
    the escape hatch (`show_rejected?`); TV stays aggregate.
  * `:nothing_live` — zero raw results, checked within the corpus
    freshness window.
  * `:nothing_stale` — zero raw results, but the knowledge is older
    than the freshness window; Search again is the remedy.
  * `:searching` — the board is still planning: the headline says what
    the descent is doing right now (`searching/1`, from a
    `PlanEvents.DescentStatus`) or, before the first event, what it is
    about to do (`searching_initial/1`). One verdict slot for the board
    in every state — the expectation panel's rows (`DescentNarrative`)
    sit beneath it and never headline (UIDR-029, audit DS24).

  Pure — the LiveView assigns the built struct (ADR-030).
  """

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.PlanEvents.DescentStatus
  alias MediaCentaur.Acquisition.ViewModels.GapEvidence
  alias MediaCentaur.Search.IndexerHealth

  import MediaCentaur.Acquisition.ViewModels.Formatting, only: [count: 2]

  @enforce_keys [:world, :headline]
  defstruct [:world, :headline, :evidence_line, rejected_count: 0, show_rejected?: false]

  @type world ::
          :blind
          | :below_preference
          | :no_evidence
          | :rejected
          | :nothing_live
          | :nothing_stale
          | :searching

  @type t :: %__MODULE__{
          world: world(),
          headline: String.t(),
          evidence_line: String.t() | nil,
          rejected_count: non_neg_integer(),
          show_rejected?: boolean()
        }

  @doc """
  Builds the verdict. Options: `gaps` (unit labels), `movie?`,
  `search_health` (`IndexerHealth.t()` or nil), `now` — plus, for the
  below-preference world (UIDR-029), `below` (`%{units: n, releases: n}`
  or nil), `wanted` and `covered`.
  """
  @spec build(GapEvidence.t() | nil, keyword()) :: t()
  def build(evidence, opts) do
    gaps = Keyword.fetch!(opts, :gaps)
    movie? = Keyword.fetch!(opts, :movie?)
    now = Keyword.fetch!(opts, :now)
    below = Keyword.get(opts, :below)

    cond do
      reason = blind_reason(Keyword.fetch!(opts, :search_health)) ->
        blind(reason, gaps)

      gaps == [] and match?(%{units: units} when units > 0, below) ->
        below_preference(evidence, below, movie?, Keyword.get(opts, :covered, 0), now)

      true ->
        diagnose(evidence, gaps, movie?, now)
    end
  end

  @planning_headline "Planning the search — broadest releases first, drilling down only for what's still missing."

  @doc "The searching verdict before the first descent event — the strategy, as a promise."
  @spec searching_initial(pos_integer()) :: t()
  def searching_initial(_wanted), do: %__MODULE__{world: :searching, headline: @planning_headline}

  @doc """
  The searching verdict for a live descent snapshot: the active rung and
  its residual. `nil` once the descent has finished — the ready board's
  verdict (or its kept releases) speaks then.
  """
  @spec searching(DescentStatus.t()) :: t() | nil
  def searching(%DescentStatus{stages: stages, wanted: wanted}) do
    cond do
      active = Enum.find(stages, &(&1.state == :active)) ->
        %__MODULE__{
          world: :searching,
          headline: active_headline(active.id, residual_before_active(stages, wanted))
        }

      Enum.all?(stages, &(&1.state == :pending)) ->
        %__MODULE__{world: :searching, headline: @planning_headline}

      true ->
        nil
    end
  end

  defp active_headline(:series, _residual),
    do: "First, looking for one release that covers the whole show…"

  defp active_headline(:seasons, residual),
    do: "Now searching season packs — #{count(residual, "episode")} still #{need(residual)} coverage…"

  defp active_headline(:episodes, residual),
    do: "Now hunting individual episodes — #{count(residual, "episode")} still uncovered…"

  defp residual_before_active(stages, wanted) do
    stages
    |> Enum.take_while(&(&1.state != :active))
    |> Enum.filter(&(&1.state == :done))
    |> List.last()
    |> case do
      nil -> wanted
      %{residual_after: residual} -> residual
    end
  end

  defp need(1), do: "needs"
  defp need(_quantity), do: "need"

  defp below_preference(evidence, %{units: units, releases: releases}, movie?, covered, now) do
    %__MODULE__{
      world: :below_preference,
      headline: below_headline(movie?, units, covered),
      evidence_line: below_evidence_line(evidence, releases, now)
    }
  end

  defp below_headline(true, _units, _covered),
    do: "This movie is available only in lower quality — nothing at your quality preference."

  defp below_headline(false, units, 0) do
    "Nothing at your quality preference — all #{count(units, "episode")} are available only in lower quality."
  end

  defp below_headline(false, units, covered) do
    verb = if covered == 1, do: "was", else: "were"

    "#{count(covered, "episode")} #{verb} found at your quality preference — the other #{units} are available only in lower quality."
  end

  defp below_evidence_line(nil, releases, _now), do: "#{count(releases, "lower-quality release")} found."

  defp below_evidence_line(%GapEvidence{checked_at: nil}, releases, _now),
    do: "#{count(releases, "lower-quality release")} found."

  defp below_evidence_line(%GapEvidence{checked_at: checked_at}, releases, now) do
    checked = age_or_just_now(DateTime.diff(now, checked_at, :second))
    "#{count(releases, "lower-quality release")} — checked #{checked}."
  end

  defp blind(reason, gaps) do
    %__MODULE__{
      world: :blind,
      headline: "Couldn't check availability — #{reason} — #{Enum.join(gaps, ", ")}"
    }
  end

  defp diagnose(nil, gaps, movie?, now),
    do:
      diagnose(
        %GapEvidence{searches: [], rejected: [], raw_total: 0, checked_at: nil},
        gaps,
        movie?,
        now
      )

  defp diagnose(%GapEvidence{searches: []}, gaps, movie?, _now) do
    %__MODULE__{
      world: :no_evidence,
      headline: "No recent search results on record for #{subject(movie?)}.",
      evidence_line: still_missing("Search again checks your indexers live.", gaps, movie?)
    }
  end

  defp diagnose(%GapEvidence{raw_total: 0} = evidence, gaps, movie?, now) do
    age_seconds = DateTime.diff(now, evidence.checked_at, :second)

    if age_seconds > Corpus.freshness_window_minutes() * 60 do
      %__MODULE__{
        world: :nothing_stale,
        headline: "Nothing in the last known results (from #{age(age_seconds)} ago).",
        evidence_line:
          still_missing(
            "#{intro(evidence, movie?)} — Search again asks your indexers live.",
            gaps,
            movie?
          )
      }
    else
      %__MODULE__{
        world: :nothing_live,
        headline: "No indexer had anything for #{subject(movie?)}.",
        evidence_line: checked_line(evidence, gaps, movie?, now)
      }
    end
  end

  defp diagnose(%GapEvidence{} = evidence, gaps, movie?, now) do
    %__MODULE__{
      world: :rejected,
      headline: rejected_headline(evidence.raw_total, movie?),
      evidence_line: checked_line(evidence, gaps, movie?, now),
      rejected_count: length(evidence.rejected),
      show_rejected?: movie? and evidence.rejected != []
    }
  end

  defp rejected_headline(1, true), do: "1 result came back, but it didn't look like this movie."
  defp rejected_headline(1, false), do: "1 result came back, but it didn't work for these episodes."

  defp rejected_headline(total, true), do: "#{total} results came back, but none looked like this movie."

  defp rejected_headline(total, false),
    do: "#{total} results came back, but none worked for these episodes."

  defp checked_line(evidence, gaps, movie?, now) do
    checked = "checked #{age_or_just_now(DateTime.diff(now, evidence.checked_at, :second))}"
    still_missing("#{intro(evidence, movie?)} — #{checked}.", gaps, movie?)
  end

  # Movies list the literal query strings (there are at most two); TV
  # ladders run too many terms to enumerate, so the count carries it.
  defp intro(evidence, true), do: "Searched #{quoted_terms(evidence.searches)}"
  defp intro(%{searches: [_single]}, false), do: "1 search"
  defp intro(evidence, false), do: "#{length(evidence.searches)} searches"

  defp quoted_terms(searches) do
    searches
    |> Enum.map(&"“#{&1.term}”")
    |> join_naturally()
  end

  defp join_naturally([term]), do: term

  defp join_naturally(terms) do
    {rest, [last]} = Enum.split(terms, -1)
    Enum.join(rest, ", ") <> " and " <> last
  end

  # The movie's identity is the modal's lockup — naming it again is
  # noise. TV gaps are specific episodes the grid alone doesn't call
  # out, so the line names them.
  defp still_missing(line, _gaps, true), do: line
  defp still_missing(line, gaps, false), do: "#{line} Still missing: #{Enum.join(gaps, ", ")}."

  defp subject(true), do: "this title"
  defp subject(false), do: "these episodes"

  @just_now_seconds 60

  defp age_or_just_now(seconds) when seconds < @just_now_seconds, do: "just now"
  defp age_or_just_now(seconds), do: "#{age(seconds)} ago"

  defp age(seconds) when seconds < 3600, do: count(div(seconds, 60), "minute")
  defp age(seconds) when seconds < 86_400, do: count(div(seconds, 3600), "hour")
  defp age(seconds), do: count(div(seconds, 86_400), "day")

  defp blind_reason(%IndexerHealth{state: :unreachable}), do: "Prowlarr is unreachable"

  defp blind_reason(%IndexerHealth{} = health) do
    if IndexerHealth.blind?(health), do: "no indexers are answering"
  end

  defp blind_reason(nil), do: nil
end
