defmodule MediaCentaurWeb.Components.Detail.PlayableRow do
  @moduledoc """
  Shared chrome for the detail modal's playable rows — the pieces an
  episode row, a collection movie row, and an extra row all render the
  same way: the watched/unwatched toggle (with its
  duration/remaining text), the thin in-progress underline, the
  state-dependent row classes, and the spoiler-blur rule.

  Keeping the three row families on one module prevents the hover/state
  styling from drifting between them — before this module the underline
  markup was copied verbatim in all three.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.LibraryFormatters, only: [format_human_duration: 1]

  alias MediaCentaur.Library.ProgressRecords

  @doc "Whether the row's item carries the watched mark; the check shows exactly then."
  defdelegate watched?(progress), to: ProgressRecords

  @doc "Whether the row's item has a viewing in flight that counts; the underline and remaining time show exactly then."
  defdelegate viewing?(progress), to: ProgressRecords

  @doc """
  Classes for a playable row, from its progress record: the resume target
  beats everything (primary wash), a row with a viewing in flight gets
  the info wash whether or not it is watched, and a watched row with no
  viewing dims.
  """
  @spec row_class(map() | nil, boolean()) :: String.t() | nil
  def row_class(_progress, true = _is_resume_target), do: "bg-primary/10"

  def row_class(progress, _is_resume_target) do
    cond do
      viewing?(progress) -> "bg-info/5"
      watched?(progress) -> "opacity-60"
      true -> nil
    end
  end

  @doc """
  Whether a row's thumbnail, title and synopsis should be
  spoiler-blurred: only when spoiler-free mode is on *and* the item has
  neither the watched mark nor a viewing in flight. A watched or
  in-progress item is never blurred (the user has already started it),
  and nothing blurs when spoiler-free mode is off.
  """
  @spec blur_spoilers?(boolean(), map() | nil) :: boolean()
  def blur_spoilers?(spoiler_free, progress),
    do: spoiler_free and not watched?(progress) and not viewing?(progress)

  @doc "Playback position as a 0–100 percent, capped."
  @spec progress_percent(map() | nil) :: non_neg_integer()
  def progress_percent(%{position_seconds: pos, duration_seconds: dur})
      when is_number(pos) and is_number(dur) and dur > 0 do
    min(round(pos / dur * 100), 100)
  end

  def progress_percent(_progress), do: 0

  @doc """
  Thin in-progress underline below a row with a viewing in flight. The
  caller guards on it (`:if={viewing?(@progress)}`) and supplies the left margin
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

  attr :progress, :map,
    default: nil,
    doc:
      "`MediaCentaur.Library.WatchProgress.t() | nil` — the record the press acts on. Its " <>
        "watched mark fills the circle and names the control (Mark unwatched when marked, " <>
        "else Mark watched); its viewing in flight renders the remaining time. A watched " <>
        "item being replayed shows both."

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
        aria-label={if watched?(@progress), do: "Mark unwatched", else: "Mark watched"}
        {@rest}
      >
        <span class={[
          "size-5 rounded-full flex items-center justify-center transition-all",
          watched_circle_class(watched?(@progress))
        ]}>
          <.icon
            :if={watched?(@progress)}
            name="hero-check-mini"
            class="size-3 text-success"
          />
          <.icon
            :if={!watched?(@progress)}
            name="hero-check-mini"
            class="size-3 opacity-0 group-hover/toggle:opacity-60 transition-opacity"
          />
        </span>
      </button>
    </div>
    """
  end

  # Duration text beside the toggle: "Xm remaining" while a viewing is in
  # flight, nothing for a watched item with none, the plain runtime
  # otherwise.
  attr :progress, :map,
    default: nil,
    doc: "`MediaCentaur.Library.WatchProgress.t() | nil`, as on `watched_toggle/1`."

  attr :duration_seconds, :integer, default: nil

  defp duration_text(assigns) do
    assigns = assign(assigns, :text, duration_text(assigns.progress, assigns.duration_seconds))

    ~H"""
    <span :if={@text} class={["text-xs", duration_text_class(@progress)]}>{@text}</span>
    """
  end

  defp duration_text(progress, duration_seconds) do
    cond do
      viewing?(progress) ->
        remaining = trunc(max((progress.duration_seconds || 0) - progress.position_seconds, 0))
        "#{format_human_duration(remaining)} remaining"

      watched?(progress) ->
        nil

      is_integer(duration_seconds) and duration_seconds > 0 ->
        format_human_duration(duration_seconds)

      true ->
        nil
    end
  end

  defp duration_text_class(progress),
    do: if(viewing?(progress), do: "text-info", else: "text-base-content/55")

  # Note: the `group-hover/toggle:` classes below depend on the toggle
  # button carrying `group/toggle` (set by `watched_toggle_button_class/0`).
  # Any caller that bypasses `watched_toggle/1` and renders this circle
  # directly must include `group/toggle` on the wrapping click target,
  # or the hover-preview check silently breaks with no test failure.
  defp watched_circle_class(true), do: "bg-success/25 group-hover/toggle:bg-success/40"

  defp watched_circle_class(false),
    do: "border border-base-content/20 group-hover/toggle:border-base-content/50"

  # Layout + hover styling for the watched/unwatched toggle button.
  # Padding (`p-1.5`) with a cancelling negative margin keeps the
  # circle's click/focus target comfortably larger than the 20px dot
  # (button convention) without affecting layout or reaching the text.
  defp watched_toggle_button_class do
    [
      "group/toggle flex items-center justify-center flex-shrink-0 cursor-pointer",
      "p-1.5 -m-1.5 pointer-coarse:size-12 pointer-coarse:p-0 pointer-coarse:-m-3.5 rounded-md transition-colors",
      "hover:bg-base-content/10"
    ]
  end
end
