defmodule MediaCentaurWeb.StatusLive.HealthBoard do
  @moduledoc """
  Pure view-model helpers for the Subsystem Health Board. Turns the
  `ErrorReports` store rollups into renderable per-subsystem view-models.
  No DB, no rendering — unit-tested in isolation (ADR-030).
  """

  @board_subsystems [
    :watcher,
    :pipeline,
    :tmdb,
    :http,
    :playback,
    :library,
    :acquisition,
    :social,
    :self_update,
    :system
  ]

  @labels %{
    watcher: "File watching",
    pipeline: "Media import",
    tmdb: "Metadata",
    http: "Connections",
    playback: "Playback",
    library: "Library",
    acquisition: "Downloads",
    social: "Social",
    self_update: "Updates",
    system: "System"
  }

  @glyphs %{
    watcher: "hero-eye",
    pipeline: "hero-arrow-down-on-square-stack",
    tmdb: "hero-film",
    http: "hero-globe-alt",
    playback: "hero-play-circle",
    library: "hero-rectangle-stack",
    acquisition: "hero-arrow-down-tray",
    social: "hero-users",
    self_update: "hero-arrow-down-circle",
    system: "hero-cpu-chip"
  }

  # Plain-language briefing for each subsystem: what it is responsible for and
  # what the experience degrades to when it isn't working. Shown at the top of
  # the drill-in so the board reads as an explanation, not just a status light.
  # One tight lede per subsystem: what it does, and — only when genuinely
  # non-obvious — what depends on it or how to recover. Consequences the
  # reader can infer from the first sentence are deliberately omitted.
  @descriptions %{
    watcher:
      "Watches your media folders and hands new files to media import. " <>
        "If it stalls, a manual scan picks up what it missed.",
    pipeline: "Turns new files into identified library entries with artwork.",
    tmdb: "Fetches metadata and artwork from The Movie Database.",
    http:
      "Every request Media Centaur makes to another server — TMDB, Prowlarr, " <>
        "your download client, GitHub — and how often the cache answered instead.",
    playback:
      "Tracks playback and records watch progress — " <>
        "resume points and Continue Watching feed off it.",
    library: "The catalog itself — titles, files, and watch state.",
    acquisition:
      "Runs downloads through Prowlarr and your download client, " <>
        "then links finished files into the library.",
    social:
      "Your identity, your relays, and the reviews, watched titles and listings that travel between you and your friends.",
    self_update: "Checks for new releases and applies in-app updates.",
    system: "Runtime health, plus anything not owned by another subsystem."
  }

  # Which configurable prerequisite each subsystem needs before it can do any
  # work at all. A subsystem absent from this map always runs (`:library`,
  # `:system`), so it is never dormant.
  @prerequisite %{
    watcher: :media_dirs,
    pipeline: :media_dirs,
    tmdb: :tmdb,
    acquisition: :acquisition,
    social: :social
  }

  # The one action that takes a dormant subsystem out of dormancy. Named for
  # the destination the reader has to reach, not for the mechanism.
  @remedies %{
    watcher: "Add a media directory under Settings → Library.",
    pipeline: "Add a media directory under Settings → Library.",
    tmdb: "Add a TMDB API key under Settings → TMDB.",
    acquisition: "Connect Prowlarr and a download client under Settings → Acquisition.",
    social: "Add a relay under Settings → Social."
  }

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.StatusLive.SubsystemView

  @spec board_subsystems() :: [atom()]
  def board_subsystems, do: @board_subsystems

  @doc """
  Builds the ordered list of subsystem tile view-models from all buckets.

  `dormant` is the set from `dormant_components/1`. Dormancy only ever
  replaces an otherwise-healthy tile: a subsystem that has actually failed
  reports the failure, configured or not.
  """
  @spec build_board([Bucket.t()], MapSet.t(atom())) :: [SubsystemView.t()]
  def build_board(buckets, dormant) do
    grouped = group_buckets(buckets)

    Enum.map(@board_subsystems, fn component ->
      %{state: state, error_count: error_count, warning_count: warning_count} =
        tile_state(grouped[component])

      %SubsystemView{
        component: component,
        label: label(component),
        glyph: glyph(component),
        state: resolve_state(state, component, dormant),
        error_count: error_count,
        warning_count: warning_count
      }
    end)
  end

  @doc """
  Groups buckets by board subsystem. Framework/unknown components fold under
  `:system`. Every board subsystem is present with at least an empty list.
  """
  @spec group_buckets([Bucket.t()]) :: %{atom() => [Bucket.t()]}
  def group_buckets(buckets) do
    base = Map.new(@board_subsystems, &{&1, []})

    buckets
    |> Enum.group_by(fn %Bucket{component: c} -> normalize(c) end)
    |> then(&Map.merge(base, &1))
  end

  @type tile_state :: %{
          state: :ok | :warning | :error,
          error_count: non_neg_integer(),
          warning_count: non_neg_integer()
        }

  @doc "Derives a tile's health state from its buckets. critical+error => :error."
  @spec tile_state([Bucket.t()]) :: tile_state()
  def tile_state(buckets) do
    error_count = Enum.count(buckets, &(&1.severity in [:error, :critical]))
    warning_count = Enum.count(buckets, &(&1.severity == :warning))

    state =
      cond do
        error_count > 0 -> :error
        warning_count > 0 -> :warning
        true -> :ok
      end

    %{state: state, error_count: error_count, warning_count: warning_count}
  end

  @spec label(atom()) :: String.t()
  def label(component), do: Map.fetch!(@labels, normalize(component))

  @spec glyph(atom()) :: String.t()
  def glyph(component), do: Map.fetch!(@glyphs, normalize(component))

  @doc "Plain-language briefing: what the subsystem does and how it degrades if it fails."
  @spec description(atom()) :: String.t()
  def description(component), do: Map.fetch!(@descriptions, normalize(component))

  @doc """
  The subsystems that cannot do any work because their prerequisite is
  unconfigured. `flags` carries one boolean per prerequisite named in
  `@prerequisite` — `%{media_dirs: bool, tmdb: bool, acquisition: bool, social:
  bool}` — supplied by the caller so this module stays pure.
  """
  @spec dormant_components(%{optional(atom()) => boolean()}) :: MapSet.t(atom())
  def dormant_components(flags) do
    for {component, prerequisite} <- @prerequisite,
        not Map.get(flags, prerequisite, true),
        into: MapSet.new(),
        do: component
  end

  @doc "The one action that takes a dormant subsystem out of dormancy."
  @spec dormant_remedy(atom()) :: String.t() | nil
  def dormant_remedy(component), do: Map.get(@remedies, normalize(component))

  @doc "Plain-language one-line summary of a tile's state (e.g. `2 errors · 1 warning`)."
  @spec tile_summary(SubsystemView.t()) :: String.t()
  def tile_summary(%SubsystemView{state: :dormant}), do: "Not configured"
  def tile_summary(%SubsystemView{state: :ok}), do: "No issues"

  def tile_summary(%SubsystemView{error_count: error_count, warning_count: warning_count}) do
    [count_phrase(error_count, "error"), count_phrase(warning_count, "warning")]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @doc "Newest-first, formatted log lines drawn from a subsystem's buckets (capped at 20)."
  @spec log_lines([Bucket.t()]) :: [String.t()]
  def log_lines(buckets) do
    buckets
    |> Enum.flat_map(& &1.sample_entries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
    |> Enum.take(20)
    |> Enum.map(fn %{timestamp: timestamp, message: message} ->
      "#{Calendar.strftime(timestamp, "%H:%M:%S")}  #{message}"
    end)
  end

  # Dormancy is a statement about capability, not about failure, so it only
  # stands in for `:ok`. Anything that actually went wrong outranks it.
  defp resolve_state(:ok, component, dormant) do
    if MapSet.member?(dormant, component), do: :dormant, else: :ok
  end

  defp resolve_state(state, _component, _dormant), do: state

  defp count_phrase(0, _word), do: nil
  defp count_phrase(1, word), do: "1 #{word}"
  defp count_phrase(n, word), do: "#{n} #{word}s"

  # The wire logs under its own `:nostr` tag but shares the Social board
  # tile — alias it before the generic fold.
  defp normalize(:nostr), do: :social
  # Framework + unknown components fold under :system on the board.
  defp normalize(component) when component in @board_subsystems, do: component
  defp normalize(_), do: :system
end
