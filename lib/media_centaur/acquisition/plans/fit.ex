defmodule MediaCentaur.Acquisition.Plans.Fit do
  @moduledoc """
  Fit — the share of a pack's span that a plan actually wants:
  wanted-in-span ÷ span-total. `Planner` gates a pack on it (a pack is
  assignable only when it fits) and `SearchOrder` orders the search by
  it (a scope whose pack could fit is searched before one whose pack
  could only be offered). Both read these two functions, so the gate
  and the order can never disagree about what fits.

  Monotonic opt-in: an unknown span total (no span sizes for a season,
  an unknown scope, an empty span) or a nil threshold is never judged —
  `fits?/3` says yes — so gating only ever removes a pack that provably
  does not fit. Pure — no I/O, no DB.
  """

  alias MediaCentaur.Search.ReleaseCoverage

  @typedoc "Per-season aired-episode counts keyed by season-number string (`Targeting.aired_counts/1`)."
  @type span_sizes :: %{String.t() => non_neg_integer()}

  @doc """
  The realistic episode count a grab of this scope lands on disk — the
  fit denominator. Episode scopes carry their own breadth; season and
  series scopes read the span sizes. `nil` means "can't tell".
  """
  @spec span_total(ReleaseCoverage.t() | :unknown, span_sizes()) :: non_neg_integer() | nil
  def span_total({:episode, _season, _episode}, _span_sizes), do: 1
  def span_total({:episodes, _season, first, last}, _span_sizes), do: last - first + 1
  def span_total({:season, season}, span_sizes), do: season_size(span_sizes, season)

  def span_total({:seasons, first, last}, span_sizes) do
    sizes = Enum.map(first..last, &season_size(span_sizes, &1))
    if Enum.all?(sizes, &is_integer/1), do: Enum.sum(sizes)
  end

  def span_total(:series, span_sizes) do
    sizes = Map.values(span_sizes)
    if sizes != [], do: Enum.sum(sizes)
  end

  def span_total(:unknown, _span_sizes), do: nil

  @doc """
  Whether wanting `wanted_in_span` of a `span_total`-episode span clears
  the threshold, inclusive. Not judged — true — when the total or the
  threshold is unknown, or the span is empty.
  """
  @spec fits?(non_neg_integer(), non_neg_integer() | nil, number() | nil) :: boolean()
  def fits?(_wanted_in_span, _span_total, nil), do: true
  def fits?(_wanted_in_span, nil, _threshold), do: true

  def fits?(wanted_in_span, span_total, threshold) when span_total > 0,
    do: wanted_in_span / span_total >= threshold

  def fits?(_wanted_in_span, _empty_span, _threshold), do: true

  defp season_size(span_sizes, season), do: Map.get(span_sizes, Integer.to_string(season))
end
