defmodule MediaCentaurWeb.Components.ActionToast do
  @moduledoc """
  A transient toast with one action — the flash skin (`.flash-toast`)
  for a message that needs a way back: "Sample Movie ignored · Undo".
  `flash/1` is layout-owned and text-only; this renders where the host
  page puts it and carries the host's own events, so the action can
  name what it undoes.

  Dismissal is one path: `on_dismiss` is the element's `phx-click`, and
  `FlashAutoDismiss` replays that same binding when the dwell runs out,
  so a click and a timeout both end in the host clearing the assign that
  rendered it. The action is a nested `phx-click`; LiveView dispatches
  the closest binding only, so the host's action handler clears the
  toast itself.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :id, :string, required: true, doc: "the action button is `<id>-action`"
  attr :message, :string, required: true
  attr :action, :string, required: true, doc: "the one action's label"
  attr :on_action, JS, required: true, doc: "pushed by the action; the handler also clears the toast"
  attr :on_dismiss, JS, required: true, doc: "pushed by a click on the toast and by expiry"

  attr :dismiss_after, :integer,
    default: 6000,
    doc: "milliseconds before `on_dismiss` replays on its own (`FlashAutoDismiss`); hover pauses it"

  def action_toast(assigns) do
    ~H"""
    <div
      id={@id}
      phx-click={@on_dismiss}
      phx-hook="FlashAutoDismiss"
      data-dismiss-after={@dismiss_after}
      role="status"
      class="toast toast-top toast-end z-50"
      data-component="action-toast"
    >
      <div class="flash-toast flex w-80 max-w-80 cursor-pointer items-center gap-3 rounded-xl p-3.5 text-wrap sm:w-96 sm:max-w-96">
        <.icon name="hero-information-circle" class="size-5 shrink-0 text-info" />
        <p class="min-w-0 flex-1 text-sm text-base-content/70">{@message}</p>
        <button
          id={"#{@id}-action"}
          type="button"
          class="shrink-0 cursor-pointer text-sm font-medium text-primary transition-colors hover:text-primary/80"
          phx-click={@on_action}
        >
          {@action}
        </button>
      </div>
    </div>
    """
  end
end
