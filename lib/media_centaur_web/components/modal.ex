defmodule MediaCentaurWeb.Components.Modal do
  @moduledoc """
  The single modal seam. Owns `modal-backdrop`/`modal-panel` — enforced by
  Credo MC0017, no other module may use those classes.

  Distilled from our best modals (`ModalShell` / `PursuitModal`): the panel is
  **always rendered in the DOM** and visibility is toggled purely via
  `data-state="open"/"closed"`, which keeps the `backdrop-filter` compositing
  layer warm so there is no first-frame blur jank on open. The backdrop/panel
  split, the `phx-click={%JS{}}` propagation-stop on the panel, and the inner
  scroll container (left to the caller's slot) all come straight from that
  proven pattern. Richer ModalShell-specific treatment (entity backdrop image,
  atmosphere scrim) stays local to that component's slot content rather than
  being hoisted here.

  The ephemeral-vs-persistent distinction is the required `dismiss` attr:

    * `:ephemeral`  — backdrop click AND Escape fire `on_close`. The default,
      lightweight pattern; use for read-only or trivially re-openable views.
    * `:persistent` — neither backdrop click nor Escape dismisses. Use when a
      casual dismissal would lose the user's in-progress work; the panel must
      supply its own explicit dismissal controls (a Cancel/Close button).

  Making `dismiss` required is the formalization: a modal cannot be mounted
  without naming its kind, and all dismissal wiring is derived from that one
  value so the two behaviors can never drift apart or be half-applied.
  """
  use Phoenix.Component

  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :dismiss, :atom, values: [:ephemeral, :persistent], required: true

  attr :on_close, :string,
    default: nil,
    doc: "event fired on backdrop click + Escape. Required for `:ephemeral`; ignored for `:persistent`."

  attr :size, :atom, values: [:md, :sm], default: :md
  attr :panel_class, :string, default: nil
  attr :rest, :global, doc: "extra attrs forwarded onto the backdrop (e.g. data-* hooks)."
  slot :inner_block, required: true

  def modal(%{dismiss: :ephemeral, on_close: nil}) do
    raise ArgumentError, "<.modal dismiss={:ephemeral}> requires an on_close event"
  end

  def modal(assigns) do
    assigns =
      assign(assigns,
        panel_size_class: if(assigns.size == :sm, do: "modal-panel-sm"),
        close_event: assigns.dismiss == :ephemeral && assigns.open && assigns.on_close
      )

    ~H"""
    <div
      id={@id}
      class="modal-backdrop"
      data-state={if @open, do: "open", else: "closed"}
      phx-click={@close_event}
      phx-window-keydown={@close_event}
      phx-key={@dismiss == :ephemeral && "Escape"}
      {@rest}
    >
      <div class={["modal-panel", @panel_size_class, @panel_class]} phx-click={%Phoenix.LiveView.JS{}}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
