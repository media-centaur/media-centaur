defmodule MediaCentaurWeb.Components.Title.TrackingControls do
  @moduledoc """
  What a listed title shows beneath its details (spec 2026-09-14,
  UIDR-042): up to two switch rows over the one record,
  `Discovery.TitleIntent`.

  * **Track release dates** — on at Follow and above. The app keeps the
    title's calendar; its dates show under Coming up on Incoming.
    Rendered only while a release is ahead (`release_ahead?`): an
    unreleased movie, or any series.
  * **Auto-grab** — on at Grab. When a release drops the app plans it;
    whether the plan commits by itself or waits for approval is the
    approval policy the person's planning mode maps to
    (`Settings.Preferences.PlanningMode.approval_policy/1`), the same
    answer the Download button gives — the host maps it once and passes
    the policy. Auto-grab implies the calendar, so while it is on the
    Track row stays on and takes no click. A movie the library already
    owns is complete (`complete?`, `ReleaseTracking.complete?/2`) and
    gets no rows at all.

  The bookmark in the action strip (`WatchlistToggle`) is the first act:
  a title with no record shows nothing here (UIDR-039), and an ignored
  title shows the one line saying the Feed hides it. `control_form/1` is
  that rule; `rows/1` decides which rows a listed title gets.

  A click pushes `set_rung` with `phx-value-choice` — the rung the row
  sets (`track_choice/1`, `grab_choice/2`), never a toggle the host has
  to interpret — and `phx-value-ref`. The rows are the Settings kit's
  toggle row (`Settings.settings_row/1`): a labelled switch that saves
  on the act is one idiom, wherever it sits. The host places the block
  above everything tracking produces (the timeline, the activity), so
  flipping a switch never moves it. A list row never wears the rows — it
  shows its rung as a quiet marker and opens its modal to change it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.Components.Settings, only: [settings_row: 1]

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.TMDB.Title

  @mode_pointer "Change this under Settings → Acquisition → Download button."

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
      "a release is still to come (`Title.Logic.release_ahead?/3`); the Track row renders only then. Always true for a series."

  attr :complete?, :boolean,
    required: true,
    doc: "nothing left to release — a movie the library owns. No rows."

  attr :approval_policy, :string,
    values: ["automatic", "review"],
    required: true,
    doc:
      "what a tracking plan is stamped with — `PlanningMode.approval_policy/1` of the person's planning mode; whether an auto-grab asks first"

  attr :acquisition?, :boolean,
    required: true,
    doc: "an indexer and a download client are ready; without them auto-grab downloads nothing"

  def tracking_controls(assigns) do
    rows = rows(assigns)
    assigns = assign(assigns, form: control_form(assigns.rung), rows: rows)

    ~H"""
    <div
      id={@id}
      class="space-y-2"
      data-component="tracking-controls"
      data-rung={@rung || :off}
      data-form={@form}
    >
      <p :if={@form == :ignored} class="text-sm text-base-content/70">{ignored_line()}</p>
      <div :if={@form == :controls} class="space-y-0.5">
        <.settings_row
          :if={:track in @rows}
          id={"#{@id}-track"}
          label="Track release dates"
          description={track_description(@media_type, @rung)}
          checked={TitleIntent.follows_releases?(@rung)}
          disabled?={is_nil(track_choice(@rung))}
          event="set_rung"
          event_value={%{"choice" => track_choice(@rung), "ref" => @ref}}
        />
        <.settings_row
          :if={:grab in @rows}
          id={"#{@id}-grab"}
          label="Auto-grab"
          description={grab_description(@media_type, @approval_policy)}
          checked={TitleIntent.grabs?(@rung)}
          event="set_rung"
          event_value={%{"choice" => grab_choice(@rung, @rows), "ref" => @ref}}
        />
      </div>
      <p
        :if={@form == :controls and :grab in @rows and !@acquisition?}
        id={"#{@id}-acquisition-note"}
        class="text-xs text-base-content/55 px-3.5"
      >
        Auto-grab downloads nothing until an indexer and a download client are set up under Settings → Acquisition.
      </p>
    </div>
    """
  end

  @doc """
  Which form the block takes (UIDR-039): `:none` for a title with no
  record — the bookmark in the action strip is its verb; `:ignored` — the
  one line saying the Feed hides it; `:controls` — the rows — for a title
  on the list.
  """
  @spec control_form(TitleIntent.rung() | nil) :: :none | :ignored | :controls
  def control_form(nil), do: :none
  def control_form(:ignored), do: :ignored
  def control_form(_listed), do: :controls

  @doc """
  Which rows a listed title gets. A movie the library owns is complete:
  none. A movie that is out has nothing left to track: Auto-grab only —
  which keeps searching until a release exists, unlike the Download
  button. A movie with a release ahead, and any series: both.
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

  @doc "What the Track row sets: Follow from List, List from Follow; nothing at Grab, which holds it on."
  @spec track_choice(TitleIntent.rung()) :: String.t() | nil
  def track_choice(:list), do: "follow"
  def track_choice(:follow), do: "list"
  def track_choice(:grab), do: nil

  @doc """
  What the Auto-grab row sets: Grab from below; from Grab, back to Follow
  when the Track row is there to show it, else List — turning off the only
  switch shown leaves the title plainly listed.
  """
  @spec grab_choice(TitleIntent.rung(), [:track | :grab]) :: String.t()
  def grab_choice(:grab, rows), do: if(:track in rows, do: "follow", else: "list")
  def grab_choice(_below_grab, _rows), do: "grab"

  @doc "The Track row's one line: what shows on Coming up, or that auto-grab holds the row on."
  @spec track_description(Title.media_type(), TitleIntent.rung()) :: String.t()
  def track_description(_media_type, :grab), do: "Stays on while auto-grab is on."

  def track_description(:movie, _rung),
    do: "Theatrical, digital and disc dates show under Coming up on Incoming."

  def track_description(:tv_series, _rung), do: "Upcoming episodes show under Coming up on Incoming."

  @doc "The Auto-grab row's line: what a drop does under the approval policy, and where that is set."
  @spec grab_description(Title.media_type(), String.t()) :: String.t()
  def grab_description(:movie, "automatic"),
    do: "The release downloads when it drops, without asking. " <> @mode_pointer

  def grab_description(:movie, "review"),
    do: "When the release drops, a plan waits for your approval on Incoming. " <> @mode_pointer

  def grab_description(:tv_series, "automatic"),
    do: "New and missing episodes download without asking. " <> @mode_pointer

  def grab_description(:tv_series, "review"),
    do: "New and missing episodes are planned and wait for your approval on Incoming. " <> @mode_pointer

  @doc "The line an ignored title shows in place of the rows."
  @spec ignored_line() :: String.t()
  def ignored_line, do: "Hidden from the Feed. Add it to your watchlist to bring it back."
end
