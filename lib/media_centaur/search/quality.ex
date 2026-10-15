defmodule MediaCentaur.Search.Quality do
  @moduledoc """
  Parses and ranks media release quality from torrent/usenet release title strings.

  Quality tiers:
  - `:uhd_4k` — 2160p, 4K, or UHD markers (preferred)
  - `:hd_1080p` — 1080p markers (acceptable)
  - `nil` — unknown or below-threshold quality (filtered out in automated grabs)
  - `:pre_release` — a cinema recording or pre-retail copy (see below)


  Manual search shows all results regardless of quality; automated grabs only
  proceed when `acceptable?/1` returns true.

  ## Pre-release sources

  A cam, telesync, telecine, screener or workprint is a copy made before
  the retail release, and its title's resolution token describes the
  encode, not the picture (`Sample.Movie.CAM-Rip.1080p`). `parse/1`
  checks for these source tokens before any resolution token and returns
  `:pre_release`. That tier is never acceptable to an automated grab,
  not even under a title's `"any"` minimum, so the owner never receives
  one without choosing it. It ranks with the unranked tier, so it still
  counts toward "lower quality available" and stays choosable by hand.
  Tokens match whole and delimited: `CAM` trips, `Camera` does not.
  Pass a release title or a file name without its extension, because a
  `.ts` container extension reads as a telesync.

  ## Source ladder (ADR-061)

  Within a resolution tier, releases are ordered by **source fidelity**,
  classified from the title's source tokens (`source/1`) and ranked by one
  of two fixed ladders (`source_rank/2`), selected by the
  `auto_grab.size_preference` setting:

  - `"fidelity"` (default): remux > WEB-DL > BluRay encode > WEBRip/HDTV
  - `"space"`: BluRay encode > WEB-DL > WEBRip/HDTV > remux

  The invariant: gates (quality bounds, red flags) may exclude; the source
  ladder only orders — a poorly-ranked source is a last resort, never a
  rejection. File size is neither a gate nor a ranking signal.
  """

  @type t :: :uhd_4k | :hd_1080p | :pre_release | nil
  @type source :: :remux | :web_dl | :bluray_encode | :webrip | :dvdrip | :hdtv | :unknown
  @type size_preference :: String.t()

  @source_ladders %{
    "fidelity" => %{remux: 4, web_dl: 3, bluray_encode: 2, dvdrip: 2, webrip: 1, hdtv: 1, unknown: 0},
    "space" => %{bluray_encode: 4, dvdrip: 4, web_dl: 3, webrip: 2, hdtv: 2, remux: 1, unknown: 0}
  }

  # Pre-release source tokens, matched as whole delimited tokens, grouped
  # by the display label each family reads as. `HD-CAM` and `CAM-Rip`
  # split on the hyphen, so the bare `cam` token covers them.
  @pre_release_sources [
    {"Cam", ~w(cam camrip hdcam hqcam)},
    {"Telesync", ~w(ts hdts telesync)},
    {"Telecine", ~w(tc hdtc telecine)},
    {"Screener", ~w(scr dvdscr bdscr screener pdvd predvd)},
    {"Workprint", ~w(workprint)}
  ]

  @token_delimiters ~r/[\s._\-\[\]\(\)]+/

  @doc "Parses a quality tier from a release title string."
  @spec parse(String.t()) :: t()
  def parse(title) do
    downcased = String.downcase(title)

    cond do
      pre_release_label(downcased) -> :pre_release
      uhd_4k?(downcased) -> :uhd_4k
      hd_1080p?(downcased) -> :hd_1080p
      true -> nil
    end
  end

  @doc "Returns a numeric rank for sorting. Higher is better."
  @spec rank(t()) :: non_neg_integer()
  def rank(:uhd_4k), do: 2
  def rank(:hd_1080p), do: 1
  def rank(:pre_release), do: 0
  def rank(nil), do: 0

  @doc "Returns true when the quality meets the minimum threshold for automated grabs."
  @spec acceptable?(t()) :: boolean()
  def acceptable?(:uhd_4k), do: true
  def acceptable?(:hd_1080p), do: true
  def acceptable?(:pre_release), do: false
  def acceptable?(nil), do: false

  @doc """
  Returns true when `quality` falls within the inclusive `[min, max]` bound.

  Bounds are storage labels (`"hd_1080p"`, `"uhd_4k"`) — the same shape used
  on `release_tracking_items` and snapshot onto each `acquisition_grabs` row.
  Callers (typically `SearchAndGrab`) MUST resolve nil overrides to global
  defaults before calling this — passing nil is not supported, since the
  function should be deterministic without reading Settings.

  `nil` quality (an unparseable release title) is never acceptable —
  except under the `"any"` minimum (a per-title "best available"
  acceptance, ADR-063 §2), which admits unranked releases. A
  `:pre_release` copy is never acceptable, under any bounds.
  """
  @spec acceptable?(t(), String.t(), String.t()) :: boolean()
  def acceptable?(:pre_release, _min, _max), do: false
  def acceptable?(nil, "any", _max), do: true
  def acceptable?(nil, _min, _max), do: false

  def acceptable?(quality, min, max) when is_binary(min) and is_binary(max) do
    q = rank(quality)
    q >= label_rank(min) and q <= label_rank(max)
  end

  @doc """
  Returns the numeric rank for a quality label string. Mirrors `rank/1`.
  Unknown labels rank as 0 so a malformed Settings entry doesn't crash
  the search worker.
  """
  @spec label_rank(String.t() | nil) :: non_neg_integer()
  def label_rank("uhd_4k"), do: 2
  def label_rank("hd_1080p"), do: 1
  # "any" — the no-minimum bound (ADR-063 §2) — ranks 0 explicitly;
  # unknown labels also rank 0 so a malformed Settings entry can't crash.
  def label_rank(_), do: 0

  @doc "Returns a short human-readable label."
  @spec label(t()) :: String.t()
  def label(:uhd_4k), do: "4K"
  def label(:hd_1080p), do: "1080p"
  def label(:pre_release), do: "Cam"
  def label(nil), do: "Unknown"

  @doc """
  Presentation-only quality label parsed from the release title.

  Unlike the two-tier ladder (`parse/1`), this also names the
  below-floor resolutions (`720p`, `576p`, `480p`) and a DVD rip with
  no resolution token, and a pre-release copy by its source (`Cam`,
  `Telesync`, `Telecine`, `Screener`, `Workprint`) — so a below-floor
  candidate reads as what it is instead of "Unknown". It never ranks: acceptability and sorting stay
  on the ladder. Returns `nil` when the title carries no quality
  signal at all (the caller labels that "Quality unknown").
  """
  @spec display_label(String.t()) :: String.t() | nil
  def display_label(title) when is_binary(title) do
    downcased = String.downcase(title)

    cond do
      label = pre_release_label(downcased) -> label
      uhd_4k?(downcased) -> "4K"
      String.contains?(downcased, "1080p") -> "1080p"
      String.contains?(downcased, "720p") -> "720p"
      String.contains?(downcased, "576p") -> "576p"
      String.contains?(downcased, "480p") -> "480p"
      String.contains?(downcased, "dvdrip") -> "DVD"
      true -> nil
    end
  end

  @doc """
  Classifies the release's source from its title tokens.

  Remux is checked first so a hybrid title (`BluRay.1080p.REMUX`) reads as
  the remux it is. Bare `WEB` is deliberately unclassified — the scene token
  is ambiguous between WEB-DL and WEBRip, and a title word containing "web"
  must never read as a source.
  """
  @spec source(String.t()) :: source()
  def source(title) when is_binary(title) do
    downcased = String.downcase(title)

    cond do
      String.contains?(downcased, "remux") -> :remux
      String.contains?(downcased, ["web-dl", "webdl", "web.dl"]) -> :web_dl
      String.contains?(downcased, ["webrip", "web-rip", "web.rip"]) -> :webrip
      String.contains?(downcased, ["bluray", "blu-ray", "bdrip", "brrip"]) -> :bluray_encode
      # Disc-encode family, lower disc (plan-board-diagnosis campaign):
      # in an SD-only world a DVD rip must deterministically beat
      # broadcast rips and unclassified encodes — before this tier
      # existed, that pick fell to pool order.
      String.contains?(downcased, ["dvdrip", "dvd-rip", "dvd.rip"]) -> :dvdrip
      String.contains?(downcased, "hdtv") -> :hdtv
      true -> :unknown
    end
  end

  @doc """
  Ranks a source on the ladder the size preference selects. Higher is
  better. An unrecognized preference falls back to the fidelity ladder so a
  malformed Settings entry can't crash a plan run.
  """
  @spec source_rank(source(), size_preference()) :: non_neg_integer()
  def source_rank(source, size_preference) do
    @source_ladders
    |> Map.get(size_preference, @source_ladders["fidelity"])
    |> Map.fetch!(source)
  end

  @doc "Presentation-only source label parsed from the release title; nil when unclassified."
  @spec source_label(String.t()) :: String.t() | nil
  def source_label(title) when is_binary(title) do
    case source(title) do
      :remux -> "Remux"
      :web_dl -> "WEB-DL"
      :bluray_encode -> "BluRay"
      :webrip -> "WEBRip"
      :hdtv -> "HDTV"
      # The display-quality chip already reads "DVD" for these titles —
      # a second identical label would be noise.
      :dvdrip -> nil
      :unknown -> nil
    end
  end

  defp pre_release_label(downcased) do
    tokens = downcased |> String.split(@token_delimiters, trim: true) |> MapSet.new()

    Enum.find_value(@pre_release_sources, fn {label, source_tokens} ->
      if Enum.any?(source_tokens, &MapSet.member?(tokens, &1)), do: label
    end)
  end

  defp uhd_4k?(downcased) do
    String.contains?(downcased, "2160p") or
      String.contains?(downcased, "4k") or
      String.contains?(downcased, " uhd") or
      String.contains?(downcased, ".uhd") or
      String.contains?(downcased, "-uhd")
  end

  defp hd_1080p?(downcased) do
    String.contains?(downcased, "1080p")
  end
end
