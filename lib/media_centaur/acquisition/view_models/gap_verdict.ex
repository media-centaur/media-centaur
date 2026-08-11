defmodule MediaCentaur.Acquisition.ViewModels.GapVerdict do
  @moduledoc """
  The gap banner's adaptive diagnosis (UIDR-022): renders a
  `GapEvidence` snapshot into the world the counts mechanically prove —
  never an inferred cause, never a bare "not available".

  Worlds, in precedence order:

  * `:blind` — the search couldn't ask anyone (UIDR-016; outranks
    everything, keeps that record's copy verbatim).
  * `:no_evidence` — no ladder term has a corpus record (never
    searched, search failed, or pruned past retention).
  * `:rejected` — raw results exist, none qualified. Movie plans get
    the escape hatch (`show_rejected?`); TV stays aggregate.
  * `:nothing_live` — zero raw results, checked within the corpus
    freshness window.
  * `:nothing_stale` — zero raw results, but the knowledge is older
    than the freshness window; Search again is the remedy.

  Pure — the LiveView assigns the built struct (ADR-030).
  """

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.ViewModels.GapEvidence
  alias MediaCentaur.Search.IndexerHealth

  import MediaCentaur.Acquisition.ViewModels.Formatting, only: [count: 2]

  @enforce_keys [:world, :headline]
  defstruct [:world, :headline, :evidence_line, rejected_count: 0, show_rejected?: false]

  @type world :: :blind | :no_evidence | :rejected | :nothing_live | :nothing_stale

  @type t :: %__MODULE__{
          world: world(),
          headline: String.t(),
          evidence_line: String.t() | nil,
          rejected_count: non_neg_integer(),
          show_rejected?: boolean()
        }

  @doc """
  Builds the verdict. Options: `gaps` (unit labels), `movie?`,
  `search_health` (`IndexerHealth.t()` or nil), `now`.
  """
  @spec build(GapEvidence.t() | nil, keyword()) :: t()
  def build(evidence, opts) do
    gaps = Keyword.fetch!(opts, :gaps)
    movie? = Keyword.fetch!(opts, :movie?)
    now = Keyword.fetch!(opts, :now)

    case blind_reason(Keyword.fetch!(opts, :search_health)) do
      nil -> diagnose(evidence, gaps, movie?, now)
      reason -> blind(reason, gaps)
    end
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
