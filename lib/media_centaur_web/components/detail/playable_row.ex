defmodule MediaCentaurWeb.Components.Detail.PlayableRow do
  @moduledoc """
  Shared chrome for the detail modal's playable rows — the pieces an
  episode row, a collection movie row, and an extra row all render the
  same way: the watched/unwatched toggle (with its state-aware
  duration/remaining text), the thin in-progress underline, the
  state-dependent row classes, and the spoiler-blur rule.

  Keeping the three row families on one module prevents the hover/state
  styling from drifting between them — before this module the underline
  markup was copied verbatim in all three.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LibraryFormatters, only: [format_human_duration: 1]

  @doc """
  Maps a `WatchProgress` record (or `nil`) to the three-state row atom.
  Delegates to the Library rule so the rendering and composition layers
  can't drift.
  """
  defdelegate state_from_progress(progress),
    to: MediaCentaur.Library.EpisodeList

  @doc """
  State-dependent classes for a playable row: resume target beats
  everything (primary wash), watched rows dim, the in-progress row gets
  the info wash.
  """
  @spec row_class(atom(), boolean()) :: String.t()
  def row_class(_state, true = _is_resume_target), do: "bg-primary/10"

  def row_class(:watched, _), do: "opacity-60"
  def row_class(:current, _), do: "bg-info/5"
  def row_class(:unwatched, _), do: ""

  @doc """
  Whether a row's thumbnail, title and synopsis should be
  spoiler-blurred: only when spoiler-free mode is on *and* the item is
  fully unwatched. A watched or in-progress item is never blurred (the
  user has already started it), and nothing blurs when spoiler-free
  mode is off.
  """
  @spec blur_spoilers?(boolean(), atom()) :: boolean()
  def blur_spoilers?(spoiler_free, state), do: spoiler_free and state == :unwatched

  @doc "Playback position as a 0–100 percent, capped."
  @spec progress_percent(map() | nil) :: non_neg_integer()
  def progress_percent(%{position_seconds: pos, duration_seconds: dur})
      when is_number(pos) and is_number(dur) and dur > 0 do
    min(round(pos / dur * 100), 100)
  end

  def progress_percent(_progress), do: 0

  @doc """
  Thin in-progress underline below a `:current` row. The caller guards
  on state (`:if={@state == :current}`) and supplies the left margin
  that aligns the track with its row's text column.
  """
  attr :progress, :map,
    required: true,
    doc: "`MediaCentaur.Library.WatchProgress.t()` — position/duration drive the fill width."

  attr :class, :any, default: nil, doc: "extra classes — typically the row-specific left margin."

  def progress_underline(assigns) do
    ~H"""
    <div class={["mt-1 h-0.5 rounded-full bg-base-content/10 overflow-hidden", @class]}>
      <div
        class="h-full bg-info rounded-full"
        style={"width: #{progress_percent(@progress)}%"}
      />
    </div>
    """
  end

  @doc """
  Shared watched/unwatched toggle button. Used by episode, movie, and
  extra rows — the only per-call differences are the `phx-click` event
  name and the `phx-value-*` attributes (forwarded via the `:rest`
  global).

  The button wraps ONLY the state circle — the duration/remaining text
  is a sibling outside it so a click on that informational text falls
  through to the row's play handler rather than toggling watched state.
  """
  attr :event, :string, required: true
  attr :state, :atom, required: true, values: [:watched, :current, :unwatched]

  attr :progress, :map,
    default: nil,
    doc:
      "`MediaCentaur.Library.WatchProgress.t() | nil` — renders the remaining time in the `:current` state."

  attr :duration_seconds, :integer, default: nil

  attr :show_duration, :boolean,
    default: true,
    doc:
      "whether the state-aware duration text renders beside the circle. Rows keep it " <>
        "(their only progress display); the collection modal's play line passes false — " <>
        "the PlayCard's progress row directly above already says it (UIDR-023)."

  attr :nav_item, :boolean,
    default: false,
    doc:
      "render the button as a first-class `data-nav-item` instead of a `data-nav-sub-item`. " <>
        "Rows keep the sub-item default (the row is the nav item); on the play line the " <>
        "toggle stands alone in a TOOLBAR zone, which only walks nav items."

  attr :rest, :global,
    doc:
      "`phx-value-*` attributes that identify the toggle target (entity + leaf container " <>
        "for `toggle_watched` — movie rows send container-type/container-id, episode rows " <>
        "still send season/episode until the leaf-id convergence lands — entity/extra for " <>
        "`toggle_extra_watched`).",
    include:
      ~w(phx-value-entity-id phx-value-season phx-value-episode phx-value-extra-id phx-value-container-type phx-value-container-id)

  def watched_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-2 flex-shrink-0">
      <.duration_text
        :if={@show_duration}
        state={@state}
        progress={@progress}
        duration_seconds={@duration_seconds}
      />
      <button
        type="button"
        phx-click={@event}
        data-nav-sub-item={!@nav_item || nil}
        data-nav-item={@nav_item || nil}
        tabindex={(@nav_item && "0") || nil}
        class={watched_toggle_button_class()}
        aria-label={if @state == :watched, do: "Mark unwatched", else: "Mark watched"}
        {@rest}
      >
        <span class={[
          "size-5 rounded-full flex items-center justify-center transition-all",
          watched_circle_class(@state)
        ]}>
          <.icon
            :if={@state == :watched}
            name="hero-check-mini"
            class="size-3 text-success"
          />
          <.icon
            :if={@state != :watched}
            name="hero-check-mini"
            class="size-3 opacity-0 group-hover/toggle:opacity-60 transition-opacity"
          />
        </span>
      </button>
    </div>
    """
  end

  # State-aware duration text beside the toggle: nothing when watched,
  # "Xm remaining" while current, the plain runtime otherwise.
  defp duration_text(%{state: :watched} = assigns) do
    ~H"""
    """
  end

  defp duration_text(%{state: :current, progress: progress} = assigns) do
    remaining = trunc(max(progress.duration_seconds - progress.position_seconds, 0))
    assigns = assign(assigns, :remaining, remaining)

    ~H"""
    <span class="text-info text-xs">
      {format_human_duration(@remaining)} remaining
    </span>
    """
  end

  defp duration_text(%{duration_seconds: seconds} = assigns) when is_integer(seconds) and seconds > 0 do
    ~H"""
    <span class="text-base-content/55 text-xs">
      {format_human_duration(@duration_seconds)}
    </span>
    """
  end

  defp duration_text(assigns) do
    ~H"""
    """
  end

  # Note: the `group-hover/toggle:` classes below depend on the toggle
  # button carrying `group/toggle` (set by `watched_toggle_button_class/0`).
  # Any caller that bypasses `watched_toggle/1` and renders this circle
  # directly must include `group/toggle` on the wrapping click target,
  # or the hover-preview check silently breaks with no test failure.
  defp watched_circle_class(:watched), do: "bg-success/25 group-hover/toggle:bg-success/40"

  defp watched_circle_class(_state),
    do: "border border-base-content/20 group-hover/toggle:border-base-content/50"

  # Layout + hover styling for the watched/unwatched toggle button.
  # Padding (`p-1.5`) with a cancelling negative margin keeps the
  # circle's click/focus target comfortably larger than the 20px dot
  # (UIDR-003) without affecting layout or reaching the text.
  defp watched_toggle_button_class do
    [
      "group/toggle flex items-center flex-shrink-0 cursor-pointer",
      "p-1.5 -m-1.5 rounded-md transition-colors",
      "hover:bg-base-content/10"
    ]
  end
end
