defmodule MediaCentaurWeb.Components.ReleaseTracking.TrackingModeControl do
  @moduledoc """
  The tracking-mode control — the other component every title surface
  mounts (UIDR-035): one pick-one-of-five for the tracking mode
  ([ADR-065]), the same control wherever a title appears, in place of a
  bell here and an automation toggle there.

  Off · Watch · Ask · Grab · Default, each a focusable nav item, the
  active one `aria-pressed`. A click pushes `set_tracking_mode` with
  `phx-value-choice` (the mode) and `phx-value-ref` (the title's
  `TitleRef` param — a page with several controls, the watchlist, needs
  to know which title). The host resolves what the click means: on a
  tracked title it moves the mode; on an untracked one it arms
  (`ReleaseTracking.arm/2`), which lists the title as part of the act —
  a consequence the copy states while the title is Off and not yet on
  the watchlist (exactly when the next click would arm), never inferred
  silently. Moving an armed title between modes lists nothing.

  Off is `:none`, the durable disarm: reversible, so it needs no
  two-click confirmation. Nothing here deletes.

  Beneath the strip: the selected mode's one-line consequence, the
  notes, and the per-title quality acceptance row with its Reset
  (`reset_lower_quality`, ADR-063 §2) when set. A list row never wears
  this control — a row shows its mode as a quiet marker and arms from
  its modal.

  [ADR-065]: `decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md`
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [button: 1]

  alias MediaCentaur.ReleaseTracking.Item

  @options [
    %{mode: :none, label: "Off"},
    %{mode: :watch, label: "Watch"},
    %{mode: :ask, label: "Ask"},
    %{mode: :grab, label: "Grab"},
    %{mode: :global, label: "Default"}
  ]

  attr :id, :string, required: true

  attr :ref, :string,
    required: true,
    doc: "the title's `MediaCentaurWeb.TitleRef.param/1`, carried on every click"

  attr :mode, :atom,
    values: [nil, :none, :watch, :ask, :grab, :global],
    default: nil,
    doc: "the tracked title's mode; nil when the title has never been tracked (reads as Off)"

  attr :default_grab_mode, :string,
    required: true,
    values: ~w(off ask all_releases),
    doc: "the global auto-grab default — what Default resolves to right now"

  attr :acquisition?, :boolean,
    required: true,
    doc: "an indexer and a download client are ready; without them the grab modes download nothing"

  attr :on_watchlist?, :boolean,
    required: true,
    doc: "false states, while the title is Off, that choosing a mode adds it to the watchlist"

  attr :lower_quality_accepted?, :boolean, default: false

  def tracking_mode_control(assigns) do
    ~H"""
    <div id={@id} class="space-y-2" data-component="tracking-mode-control" data-mode={@mode || :none}>
      <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">Tracking</h3>
      <div class="flex flex-wrap gap-1" role="group" aria-label="Tracking mode">
        <button
          :for={option <- options()}
          id={"#{@id}-#{option.mode}"}
          type="button"
          phx-click="set_tracking_mode"
          phx-value-choice={option.mode}
          phx-value-ref={@ref}
          aria-pressed={to_string(selected?(@mode, option.mode))}
          class={[
            "cursor-pointer rounded-md px-2.5 py-1 text-sm transition-colors duration-150",
            selected?(@mode, option.mode) && "bg-primary font-medium text-primary-content",
            !selected?(@mode, option.mode) && "text-base-content/60 hover:bg-base-content/[0.06]"
          ]}
          data-nav-item
          tabindex="0"
        >
          {option.label}
        </button>
      </div>
      <p class="text-sm text-base-content/70">{description(@mode, @default_grab_mode)}</p>
      <p :if={!@acquisition?} id={"#{@id}-acquisition-note"} class="text-xs text-base-content/55">
        Ask, Grab and Default download nothing until an indexer and a download client are set up under Settings → Acquisition.
      </p>
      <p
        :if={!@on_watchlist? and @mode in [nil, :none]}
        id={"#{@id}-watchlist-note"}
        class="text-xs text-base-content/55"
      >
        Choosing a mode adds this title to your watchlist.
      </p>
      <%!-- The per-title quality acceptance (ADR-063 §2) lives on the
            tracked title; a plan board sets it, this is where it is reset
            once the board is gone. Rendered only when set — the inherited
            default is not a fact worth a row. --%>
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

  @doc "The five modes in display order, each `%{mode, label}`."
  @spec options() :: [%{mode: Item.tracking_mode(), label: String.t()}]
  def options, do: @options

  @doc "Whether `option` is the pressed one; an untracked title (nil) reads as Off."
  @spec selected?(Item.tracking_mode() | nil, Item.tracking_mode()) :: boolean()
  def selected?(nil, option), do: option == :none
  def selected?(mode, option), do: mode == option

  @doc """
  The one-line consequence of a mode. Default spells out what the global
  auto-grab setting resolves to right now (`Item.grab_mode/2`), so the
  person never has to know the setting to know what the title will do.
  """
  @spec description(Item.tracking_mode() | nil, String.t()) :: String.t()
  def description(mode, _default) when mode in [nil, :none], do: "Not following releases."
  def description(:watch, _default), do: "Releases show on Coming up. Nothing downloads."
  def description(:ask, _default), do: "When a release drops, a plan waits for your approval."
  def description(:grab, _default), do: "Each release downloads when it drops."

  def description(:global, default) do
    "Follows the auto-grab setting, currently #{label_for_grab_mode(Item.grab_mode(:global, default))}."
  end

  defp label_for_grab_mode("all_releases"), do: "Grab"
  defp label_for_grab_mode("ask"), do: "Ask"
  defp label_for_grab_mode(_off), do: "Watch"
end
