defmodule MediaCentaurWeb.Components.Title.IntentControl do
  @moduledoc """
  The one control for a title, mounted by every title surface (UIDR-035):
  a pick-one-of-six for the rung a person's `Discovery.TitleIntent` sits
  at.

      Off · List · Follow · Ask · Grab · Default

  It replaces two controls that expressed one ladder — a watchlist
  Add/Remove *and* a five-value tracking-mode strip — which could
  contradict each other, since removing from the watchlist while at Grab
  was a legal click that tore the tracking down as a side effect. There
  is one ladder, so there is one control.

  A click pushes `set_rung` with `phx-value-choice` (the rung, or `off`)
  and `phx-value-ref` (the title's `TitleRef` param — a page with several
  controls, the watchlist, needs to know which title). Off is the absence
  of a record, so choosing it deletes the title's intent and everything
  derived from it; the consequence line says so before the click, which
  is why it needs no second confirmation.

  The rungs sit in one segmented control (the house pick-one pill the
  library's type tabs wear), a rule before Default, whose segment names
  what the global setting resolves to right now ("Default · Grab") so
  the resolved rung is on the button, not only in the line below.
  Beneath the strip: the selected rung's one-line consequence, the
  notes, and the per-title quality acceptance row with its Reset
  (`reset_lower_quality`, ADR-063 §2) when set. The host places the
  control above everything the ladder produces (the timeline, the
  activity), so choosing a rung never moves it. A list row never wears
  this control — a row shows its rung as a quiet marker and opens its
  modal to change it.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.Discovery.TitleIntent

  @options [
    %{rung: :off, label: "Off"},
    %{rung: :list, label: "List"},
    %{rung: :follow, label: "Follow"},
    %{rung: :ask, label: "Ask"},
    %{rung: :grab, label: "Grab"},
    %{rung: :default, label: "Default"}
  ]

  attr :id, :string, required: true

  attr :ref, :string,
    required: true,
    doc: "the title's `MediaCentaurWeb.TitleRef.param/1`, carried on every click"

  attr :rung, :atom,
    values: [nil, :list, :follow, :ask, :grab, :default],
    default: nil,
    doc: "the rung the title's intent sits at; nil means the title is Off — no record"

  attr :default_grab_mode, :string,
    required: true,
    values: ~w(off ask all_releases),
    doc: "the global auto-grab default — what Default resolves to right now"

  attr :acquisition?, :boolean,
    required: true,
    doc: "an indexer and a download client are ready; without them the grab rungs download nothing"

  attr :lower_quality_accepted?, :boolean, default: false

  def intent_control(assigns) do
    ~H"""
    <div id={@id} class="space-y-2.5" data-component="intent-control" data-rung={@rung || :off}>
      <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">Tracking</h3>
      <div class="tabs tabs-boxed segmented-control w-fit" role="group" aria-label="Tracking">
        <%= for option <- options() do %>
          <span :if={option.rung == :default} class="segment-rule" aria-hidden="true"></span>
          <button
            id={"#{@id}-#{option.rung}"}
            type="button"
            class={["tab", "text-sm"]}
            phx-click="set_rung"
            phx-value-choice={option.rung}
            phx-value-ref={@ref}
            aria-pressed={to_string(selected?(@rung, option.rung))}
            data-nav-item
            tabindex="0"
          >
            {segment_label(option, @default_grab_mode)}
          </button>
        <% end %>
      </div>
      <p class="text-sm text-base-content/70">{description(@rung)}</p>
      <p :if={!@acquisition?} id={"#{@id}-acquisition-note"} class="text-xs text-base-content/55">
        Ask, Grab and Default download nothing until an indexer and a download client are set up under Settings → Acquisition.
      </p>
      <%!-- The per-title quality acceptance (ADR-063 §2) is keyed by TMDB
            identity, so it can be set on a title at any rung; a plan board
            sets it, this is where it is reset once the board is gone.
            Rendered only when set — the inherited default is not a fact
            worth a row. --%>
      <div
        :if={@lower_quality_accepted?}
        id={"#{@id}-lower-quality"}
        class="flex items-center justify-between gap-3 pt-1"
      >
        <span class="text-sm text-base-content/80">
          Lower quality accepted — takes the best release there is
        </span>
        <.button
          variant="dismiss"
          size="xs"
          phx-click="reset_lower_quality"
          phx-value-ref={@ref}
          data-nav-item
          tabindex="0"
        >
          Reset
        </.button>
      </div>
    </div>
    """
  end

  @doc "The six rungs in ladder order, each `%{rung, label}`. `:off` is the absence of a record."
  @spec options() :: [%{rung: TitleIntent.rung() | :off, label: String.t()}]
  def options, do: @options

  @doc "Whether `option` is the pressed one; a title with no record (nil) reads as Off."
  @spec selected?(TitleIntent.rung() | nil, TitleIntent.rung() | :off) :: boolean()
  def selected?(nil, option), do: option == :off
  def selected?(rung, option), do: rung == option

  @doc """
  The segment's label: the rung's name, and for Default what the global
  setting resolves to right now ("Default · Grab"), so the resolved rung
  is on the button itself.
  """
  @spec segment_label(%{rung: TitleIntent.rung() | :off, label: String.t()}, String.t()) ::
          String.t()
  def segment_label(%{rung: :default, label: label}, default),
    do: "#{label} · #{label_for_grab_mode(TitleIntent.grab_mode(:default, default))}"

  def segment_label(%{label: label}, _default), do: label

  @doc """
  The one-line consequence of a rung. Off states that it deletes, because
  it does and there is no confirmation step to state it later. Default
  says what it follows and where that is set; what it resolves to right
  now is on the segment itself (`segment_label/2`).
  """
  @spec description(TitleIntent.rung() | nil) :: String.t()
  def description(nil), do: "Not on your list."

  def description(:list), do: "On your list. Nothing is watching for releases."
  def description(:follow), do: "Releases show on Coming up. Nothing downloads."
  def description(:ask), do: "When a release drops, a plan waits for your approval."
  def description(:grab), do: "Each release downloads when it drops."
  def description(:default), do: "Follows the auto-grab setting under Settings → Acquisition."

  defp label_for_grab_mode("all_releases"), do: "Grab"
  defp label_for_grab_mode("ask"), do: "Ask"
  defp label_for_grab_mode(_off), do: "Follow"
end
