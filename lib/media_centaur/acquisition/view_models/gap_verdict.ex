defmodule MediaCentaur.Acquisition.ViewModels.GapVerdict do
  @moduledoc """
  The gap banner's adaptive diagnosis (UIDR-022): renders a
  `GapEvidence` snapshot into the world the counts mechanically prove —
  never an inferred cause, never a bare "not available".

  Worlds, in precedence order:

  * `:blind` — the search couldn't ask anyone (UIDR-016; outranks
    everything, keeps that record's copy verbatim). The sentence comes
    from `ViewModels.SearchOutage`, so it says what the availability
    value says and lasts exactly as long as the outage.
  * `:below_preference` — every remaining unit has releases, all below
    the quality preference (UIDR-029). Applies only when there are no
    bare gaps: a bare gap's diagnosis (below) outranks it. Never says
    "floor" — user copy calls it the quality preference.
  * `:unreleased` / `:in_theaters` — the calendar worlds (spec
    2026-09-14): a movie whose `TMDB.ReleaseWindow` says no home
    release exists yet, so no search could have found one. The
    headline speaks the dates; the evidence line, rejected count and
    escape hatch are the underlying search diagnosis's, carried
    through — the receipts are still true. Movies only: a series plan
    wants aired episodes by construction. Outranked by blind (fix the
    fault regardless) and by below-preference (real releases exist, so
    "not out" would be false).
  * `:no_evidence` — no search term has a corpus record (never
    searched, search failed, or pruned past retention).
  * `:rejected` — raw results exist, none qualified. Movie plans get
    the escape hatch (`show_rejected?`); TV stays aggregate.
  * `:nothing_live` — zero raw results, checked within the corpus
    freshness window.
  * `:nothing_stale` — zero raw results, but the knowledge is older
    than the freshness window; Search again is the remedy.
  * `:searching` — the board is still planning: the headline says what
    the search is doing right now (`searching/1`, from a
    `PlanEvents.SearchProgress`) or, before the first event, what it is
    about to do (`searching_initial/1`). One verdict slot for the board
    in every state — the expectation panel's rows (`SearchProgressPanel`)
    sit beneath it and never headline (UIDR-029, audit DS24).

  Pure — the LiveView assigns the built struct (ADR-030).
  """

  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.PlanEvents.SearchProgress
  alias MediaCentaur.Acquisition.ViewModels.GapEvidence
  alias MediaCentaur.Format
  alias MediaCentaur.TMDB.ReleaseWindow

  import MediaCentaur.Acquisition.ViewModels.Formatting, only: [count: 2]

  @enforce_keys [:world, :headline]
  defstruct [:world, :headline, :evidence_line, rejected_count: 0, show_rejected?: false]

  @type world ::
          :blind
          | :below_preference
          | :unreleased
          | :in_theaters
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
  `blind_reason` (`ViewModels.SearchOutage.reason/0`'s sentence, or nil
  when a search can answer), `now` — plus, for the
  below-preference world (UIDR-029), `below` (`%{units: n, releases: n}`
  or nil), `wanted` and `covered`; and, for the calendar worlds,
  `release_window` (`ReleaseWindow.t()` or nil, read at `now`'s date).
  """
  @spec build(GapEvidence.t() | nil, keyword()) :: t()
  def build(evidence, opts) do
    gaps = Keyword.fetch!(opts, :gaps)
    movie? = Keyword.fetch!(opts, :movie?)
    now = Keyword.fetch!(opts, :now)
    below = Keyword.get(opts, :below)
    window = Keyword.get(opts, :release_window)

    cond do
      reason = Keyword.fetch!(opts, :blind_reason) ->
        blind(reason, gaps)

      gaps == [] and match?(%{units: units} when units > 0, below) ->
        below_preference(evidence, below, movie?, Keyword.get(opts, :covered, 0), now)

      world = movie? and calendar_world(window) ->
        calendar(world, window, diagnose(evidence, gaps, movie?, now), DateTime.to_date(now))

      true ->
        diagnose(evidence, gaps, movie?, now)
    end
  end

  defp calendar_world(%ReleaseWindow{stage: :unreleased}), do: :unreleased
  defp calendar_world(%ReleaseWindow{stage: :theatrical}), do: :in_theaters
  defp calendar_world(_absent_or_out), do: nil

  # The search diagnosis keeps its receipts; only the world and the
  # sentence change.
  defp calendar(world, window, %__MODULE__{} = diagnosis, today) do
    %{diagnosis | world: world, headline: calendar_headline(world, window, today)}
  end

  defp calendar_headline(:in_theaters, %ReleaseWindow{} = window, today) do
    since = "In theaters since #{calendar_day(window.theatrical, today)}"

    case ReleaseWindow.home_release(window) do
      {type, date} -> "#{since} — #{home_phrase(type, date, today)}."
      nil -> "#{since} — TMDB has no home release date yet."
    end
  end

  defp calendar_headline(:unreleased, %ReleaseWindow{} = window, today) do
    home = ReleaseWindow.home_release(window)

    what =
      cond do
        window.theatrical && home ->
          {type, date} = home
          "in theaters from #{calendar_day(window.theatrical, today)}, #{home_phrase(type, date, today)}"

        window.theatrical ->
          "in theaters from #{calendar_day(window.theatrical, today)}"

        home ->
          {type, date} = home
          home_phrase(type, date, today)

        true ->
          "releases #{calendar_day(window.primary, today)}"
      end

    "Not out yet — #{what}."
  end

  defp home_phrase(:digital, date, today), do: "digital release #{calendar_day(date, today)}"
  defp home_phrase(:physical, date, today), do: "on disc #{calendar_day(date, today)}"

  # The year rides along only when it is not this year.
  defp calendar_day(%Date{year: year} = date, %Date{year: year}), do: Format.month_day(date)
  defp calendar_day(%Date{} = date, _today), do: "#{Format.month_day(date)}, #{date.year}"

  @planning_headline "Planning the search — right-sized releases first, wider packs only for what's still missing."

  @doc "The searching verdict before the first progress event — the strategy, as a promise."
  @spec searching_initial(pos_integer()) :: t()
  def searching_initial(_wanted), do: %__MODULE__{world: :searching, headline: @planning_headline}

  @doc """
  The searching verdict for a live progress snapshot: the active step
  and its residual. `nil` once the search has finished — the ready
  board's verdict (or its kept releases) speaks then.
  """
  @spec searching(SearchProgress.t()) :: t() | nil
  def searching(%SearchProgress{steps: steps, wanted: wanted}) do
    cond do
      active = Enum.find(steps, &(&1.state == :active)) ->
        %__MODULE__{
          world: :searching,
          headline: active_headline(active.scope, active.kind, residual_before_active(steps, wanted))
        }

      Enum.all?(steps, &(&1.state == :pending)) ->
        %__MODULE__{world: :searching, headline: @planning_headline}

      true ->
        nil
    end
  end

  # A primary step may assign what it finds; a fallback step only looks
  # for a pack to offer — the copy says which, so the user is never
  # surprised by an offer where they expected a grab.
  defp active_headline(:series, :primary, _residual), do: "Searching for a complete-series release…"

  defp active_headline(:season, :primary, residual),
    do: "Searching for season packs — #{count(residual, "episode")} still missing…"

  defp active_headline(:episode, :primary, 1), do: "Searching for the missing episode…"

  defp active_headline(:episode, :primary, residual),
    do: "Searching for the #{residual} missing episodes one by one…"

  defp active_headline(:season, :fallback, residual),
    do: "Looking for a season pack to offer for the #{count(residual, "episode")} still missing…"

  defp active_headline(:series, :fallback, _residual), do: "Looking for a complete-series pack to offer…"

  defp residual_before_active(steps, wanted) do
    steps
    |> Enum.take_while(&(&1.state != :active))
    |> Enum.filter(&(&1.state == :done))
    |> List.last()
    |> case do
      nil -> wanted
      %{residual_after: residual} -> residual
    end
  end

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
  # searches run too many terms to enumerate, so the count carries it.
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
end
