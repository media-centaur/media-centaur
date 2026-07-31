defmodule MediaCentaurWeb.Components.Acquisition.ReleaseFacts do
  @moduledoc """
  The one vocabulary for a release candidate's facts, everywhere a
  release is listed — board release rows, the swap/below-floor pickers,
  the pursuit decision card, and the naked release-search zone:

      [scope] QUALITY Release.Title.As.Filename… ⚠ looks fake 1.4 GB ▲ 42 indexer

  * **quality** — tier-colored bold label (4K healthy-green, 1080p info,
    muted otherwise, "Unknown" when the release doesn't say). Plain
    colored text, never a badge (UIDR-002 #1). Accepts the search
    ladder's atoms and the plan board's pre-labeled strings.
  * **title** — monospace: a release name is a filename (house rule —
    monospace is for functional identifiers).
  * **size** — decimal units (`Format.format_size_decimal`), what
    indexers advertise.
  * **seeders** — `▲ n`, health-colored (≥10 healthy, ≥3 thin, else
    dying). Color is signal.
  * **suspicious?** — the executable-bait flag ("looks fake").

  Pure facts, no verbs: callers own the row container (glass row,
  selection button) and the actions beside it.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Format
  alias MediaCentaur.Search.Quality

  defmodule Entry do
    @moduledoc """
    One release's displayable facts — the shared shape every listing
    surface maps its own release struct into.
    """

    @enforce_keys [:title]
    defstruct [:title, :scope_label, :quality, :size_bytes, :seeders, :indexer, suspicious?: false]

    @type t :: %__MODULE__{
            title: String.t(),
            scope_label: String.t() | nil,
            quality: atom() | String.t() | nil,
            size_bytes: integer() | nil,
            seeders: integer() | nil,
            indexer: String.t() | nil,
            suspicious?: boolean()
          }
  end

  attr :entry, Entry, required: true

  def release_facts(assigns) do
    ~H"""
    <.badge :if={@entry.scope_label} variant="ghost" size="xs" class="flex-shrink-0">
      {@entry.scope_label}
    </.badge>
    <span class={["flex-shrink-0 text-xs font-bold", quality_color(@entry.quality)]}>
      {quality_label(@entry.quality)}
    </span>
    <span
      class="min-w-0 flex-1 truncate font-mono text-[13px] text-base-content/60"
      title={@entry.title}
    >
      {@entry.title}
    </span>
    <span
      :if={@entry.suspicious?}
      class="flex-shrink-0 text-[10px] uppercase tracking-wider text-error/80"
      title="The release name looks like executable bait — only grab it if you're sure."
    >
      ⚠ looks fake
    </span>
    <span :if={@entry.size_bytes} class="flex-shrink-0 text-sm text-base-content/50 tabular-nums">
      {Format.format_size_decimal(@entry.size_bytes)}
    </span>
    <span
      :if={@entry.seeders}
      class={["flex-shrink-0 text-sm tabular-nums", seeder_color(@entry.seeders)]}
    >
      ▲ {@entry.seeders}
    </span>
    <span :if={@entry.indexer} class="flex-shrink-0 max-w-24 truncate text-xs text-base-content/40">
      {@entry.indexer}
    </span>
    """
  end

  @doc """
  Tier color for a quality value — the same signal whether the caller
  holds the search ladder's atom or the plan board's label string.
  """
  @spec quality_color(atom() | String.t() | nil) :: String.t()
  def quality_color(quality) when quality in [:uhd_4k, "4K", "2160p"], do: "text-success"
  def quality_color(quality) when quality in [:hd_1080p, "1080p"], do: "text-info"
  def quality_color(nil), do: "text-base-content/40"
  def quality_color(_other), do: "text-base-content/60"

  @doc "Displayable quality label — atoms via `Quality.label/1`, strings as-is, nil honest."
  @spec quality_label(atom() | String.t() | nil) :: String.t()
  def quality_label(quality) when is_binary(quality), do: quality
  def quality_label(quality), do: Quality.label(quality)

  @doc "Seeder-health color: ≥10 healthy, ≥3 thin, otherwise dying."
  @spec seeder_color(integer()) :: String.t()
  def seeder_color(seeders) when seeders >= 10, do: "text-success/80"
  def seeder_color(seeders) when seeders >= 3, do: "text-warning/80"
  def seeder_color(_seeders), do: "text-error/80"
end
