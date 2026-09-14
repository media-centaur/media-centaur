defmodule MediaCentaurWeb.Components.Title.TrackingControls do
  @moduledoc """
  What a listed title shows beside its release dates (spec 2026-09-14,
  UIDR-042): up to two compact switches over the one record,
  `Discovery.TitleIntent`.

  * **Notify you via Coming up** — on at Follow and above. The app keeps
    the title's calendar and its dates show under Coming up on Incoming.
    Rendered only while a release is ahead (`release_ahead?`): an
    unreleased movie, or any series.
  * **Auto-grab** — on at Grab. When a release drops the app plans it;
    whether the plan commits by itself or waits for approval is the
    approval policy the person's planning mode maps to
    (`Settings.Preferences.PlanningMode.approval_policy/1`), the same
    answer the Download button gives — the host maps it once and passes
    the policy. Auto-grab implies the calendar, so while it is on the
    Notify switch stays on and takes no click. A movie the library
    already owns is complete (`complete?`, `ReleaseTracking.complete?/2`)
    and gets no switches at all.

  The bookmark in the action strip (`WatchlistToggle`) is the first act:
  a title with no record shows nothing here (UIDR-039), and an ignored
  title shows the one line saying the Feed hides it. `control_form/1` is
  that rule; `rows/1` decides which switches a listed title gets.

  A switch is a toggle glyph and its label, the whole thing one click
  (`role="switch"`, `aria-checked`), narrow enough to sit beside the
  dates readout. A click pushes `set_rung` with `phx-value-choice` — the
  rung the switch sets (`track_choice/1`, `grab_choice/2`), never a
  toggle the host has to interpret — and `phx-value-ref`. A list row
  never wears the switches — it shows its rung as a quiet marker and
  opens its modal to change them.
  """

  use Phoenix.Component

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.TMDB.Title

  attr :id, :string, required: true

  attr :ref, :string,
    required: true,
    doc: "the title's `MediaCentaurWeb.TitleRef.param/1`, carried on every click"

  attr :rung, :atom,
    values: [nil, :ignored, :list, :follow, :grab],
    default: nil,
    doc: "the rung the title's intent sits at; nil means the title is Off — no record"

  attr :media_type, :atom, values: [:movie, :tv_series], required: true

  attr :release_ahead?, :boolean,
    required: true,
    doc:
      "a release is still to come (`Title.Logic.release_ahead?/3`); the Notify switch renders only then. Always true for a series."

  attr :complete?, :boolean,
    required: true,
    doc: "nothing left to release — a movie the library owns. No switches."

  attr :approval_policy, :string,
    values: ["automatic", "review"],
    required: true,
    doc:
      "what a tracking plan is stamped with — `PlanningMode.approval_policy/1` of the person's planning mode; whether an auto-grab asks first"

  attr :acquisition?, :boolean,
    required: true,
    doc: "an indexer and a download client are ready; without them auto-grab downloads nothing"

  attr :class, :string, default: nil

  def tracking_controls(assigns) do
    rows = rows(assigns)
    assigns = assign(assigns, form: control_form(assigns.rung), rows: rows)

    ~H"""
    <div
      id={@id}
      class={["space-y-2", @class]}
      data-component="tracking-controls"
      data-rung={@rung || :off}
      data-form={@form}
    >
      <p :if={@form == :ignored} class="text-sm text-base-content/70">{ignored_line()}</p>
      <div :if={@form == :controls} class="space-y-1">
        <.switch
          :if={:track in @rows}
          id={"#{@id}-track"}
          label="Notify you via Coming up"
          description={track_description(@media_type, @rung)}
          checked={TitleIntent.follows_releases?(@rung)}
          choice={track_choice(@rung)}
          ref={@ref}
        />
        <.switch
          :if={:grab in @rows}
          id={"#{@id}-grab"}
          label="Auto-grab"
          description={grab_description(@media_type, @approval_policy)}
          checked={TitleIntent.grabs?(@rung)}
          choice={grab_choice(@rung, @rows)}
          ref={@ref}
        />
      </div>
      <p
        :if={@form == :controls and :grab in @rows and !@acquisition?}
        id={"#{@id}-acquisition-note"}
        class="text-xs text-base-content/55"
      >
        Auto-grab downloads nothing until an indexer and a download client are set up under Settings → Acquisition.
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :description, :string, required: true
  attr :checked, :boolean, required: true

  attr :choice, :string,
    default: nil,
    doc: "the rung a click sets; nil means the switch is held and takes no click"

  attr :ref, :string, required: true

  # The toggle glyph and its words as one click. Held (no choice): no
  # click, `aria-disabled`, and the description says why; it keeps its
  # place so the nav graph never shifts.
  defp switch(assigns) do
    ~H"""
    <div
      id={@id}
      role="switch"
      aria-checked={to_string(@checked)}
      aria-disabled={is_nil(@choice) && "true"}
      class={[
        "-mx-2 flex items-start gap-3 rounded-lg px-2 py-1.5 transition-colors duration-150",
        if(is_nil(@choice), do: "opacity-60", else: "cursor-pointer hover:bg-base-content/[0.04]")
      ]}
      data-nav-item
      tabindex="0"
      phx-click={@choice && "set_rung"}
      phx-value-choice={@choice}
      phx-value-ref={@ref}
    >
      <input
        type="checkbox"
        class="toggle toggle-sm toggle-info pointer-events-none mt-0.5"
        checked={@checked}
        tabindex="-1"
      />
      <span class="min-w-0">
        <span class="block text-sm font-medium leading-tight">{@label}</span>
        <span class="block text-xs text-base-content/55">{@description}</span>
      </span>
    </div>
    """
  end

  @doc """
  Which form the block takes (UIDR-039): `:none` for a title with no
  record — the bookmark in the action strip is its verb; `:ignored` — the
  one line saying the Feed hides it; `:controls` — the switches — for a
  title on the list.
  """
  @spec control_form(TitleIntent.rung() | nil) :: :none | :ignored | :controls
  def control_form(nil), do: :none
  def control_form(:ignored), do: :ignored
  def control_form(_listed), do: :controls

  @doc """
  Which switches a listed title gets. A movie the library owns is
  complete: none. A movie that is out has nothing left to be told about:
  Auto-grab only — which keeps searching until a release exists, unlike
  the Download button. A movie with a release ahead, and any series: both.
  """
  @spec rows(%{
          required(:media_type) => Title.media_type(),
          required(:release_ahead?) => boolean(),
          required(:complete?) => boolean(),
          optional(atom()) => term()
        }) :: [:track | :grab]
  def rows(%{complete?: true}), do: []
  def rows(%{media_type: :movie, release_ahead?: false}), do: [:grab]
  def rows(_movie_ahead_or_series), do: [:track, :grab]

  @doc "What the Notify switch sets: Follow from List, List from Follow; nothing at Grab, which holds it on."
  @spec track_choice(TitleIntent.rung()) :: String.t() | nil
  def track_choice(:list), do: "follow"
  def track_choice(:follow), do: "list"
  def track_choice(:grab), do: nil

  @doc """
  What the Auto-grab switch sets: Grab from below; from Grab, back to
  Follow when the Notify switch is there to show it, else List — turning
  off the only switch shown leaves the title plainly listed.
  """
  @spec grab_choice(TitleIntent.rung(), [:track | :grab]) :: String.t()
  def grab_choice(:grab, rows), do: if(:track in rows, do: "follow", else: "list")
  def grab_choice(_below_grab, _rows), do: "grab"

  @doc "The Notify switch's line: which dates Coming up will carry, or that auto-grab holds it on."
  @spec track_description(Title.media_type(), TitleIntent.rung()) :: String.t()
  def track_description(_media_type, :grab), do: "Stays on while auto-grab is on."
  def track_description(:movie, _rung), do: "Its theatrical, digital and disc dates, as TMDB posts them."
  def track_description(:tv_series, _rung), do: "Its new episodes, as TMDB posts their air dates."

  @doc "The Auto-grab switch's line: what a drop does under the approval policy."
  @spec grab_description(Title.media_type(), String.t()) :: String.t()
  def grab_description(:movie, "automatic"), do: "Downloads when it drops."
  def grab_description(:movie, "review"), do: "Plans when it drops and waits for your approval."
  def grab_description(:tv_series, "automatic"), do: "Downloads episodes as they air."

  def grab_description(:tv_series, "review"),
    do: "Plans episodes as they air and waits for your approval."

  @doc "The line an ignored title shows in place of the switches."
  @spec ignored_line() :: String.t()
  def ignored_line, do: "Hidden from the Feed. Add it to your watchlist to bring it back."
end
