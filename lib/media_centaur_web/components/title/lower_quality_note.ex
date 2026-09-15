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

  One title detail (UIDR-043), one acceptance, one place for it — and
  which place follows the one fact that differs: whether the title has
  files.

  * **Owned** — the Manage sheet behind the cog, above the file ledger.
    It is a setting you reset once, not something to read past on the way
    to the episode list.
  * **Unowned** — there is no Manage sheet, so it sits with the tracking
    controls, where every other acquisition setting on that title lives.

  `Detail.Logic.lower_quality_note?/1` is that rule; the tracking card
  asks it rather than reading the acceptance directly. Until 2026-09-15
  the card read the acceptance itself and an owned title showed the note
  in both places at once.
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
