defmodule MediaCentaurWeb.Components.Title.LowerQualityNote do
  @moduledoc """
  The per-title lower-quality acceptance and the button that clears it.

  A plan board sets the acceptance when the person takes a release below
  their quality floor (ADR-063 §2). It is keyed by TMDB identity, not by a
  tracked title, so it outlives both the plan and the title's rung — and
  once the board is gone there is nowhere else to undo it. This is that
  place.

  Rendered only when the acceptance is set: the inherited default is not a
  fact worth a row.

  ## Where it goes

  Two surfaces show it, and they place it differently because they are
  shaped differently.

  * The **title detail modal** (Discovery, Incoming) has no Manage sheet,
    so it sits with the tracking controls, which is where every other
    acquisition setting on that surface lives.
  * The **library detail modal** puts it in the Manage sheet behind the
    cog, above the file ledger. It is a setting you reset once, not
    something to read past on the way to the episode list — and it moved
    there on 2026-09-13 because sitting under the episode list is exactly
    what it is not.
  """
  use MediaCentaurWeb, :html

  attr :id, :string, required: true

  attr :ref, :string,
    required: true,
    doc: "the title ref the reset acts on — `MediaCentaur.TMDB.Title.ref/1`."

  attr :accepted?, :boolean,
    required: true,
    doc: "whether the acceptance is set. False renders nothing."

  attr :class, :string, default: nil

  def lower_quality_note(assigns) do
    ~H"""
    <div
      :if={@accepted?}
      id={@id}
      class={["flex items-center justify-between gap-3", @class]}
      data-role="lower-quality-note"
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
    """
  end
end
