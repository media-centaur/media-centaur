defmodule MediaCentaurWeb.Components.Settings.BindingRow do
  @moduledoc """
  One binding in Settings → Controls (UIDR-041, amended 2026-10-15): the
  action's name and description, then its two slots — the key and the
  gamepad button — each drawn as a keycap. A keycap is the button that
  rebinds its slot: press it and the row listens for the next key or
  button. Unbind beside each keycap leaves the slot empty; it is inert
  (`aria-disabled`, no click) while the slot already is, and keeps its
  place so the nav graph never shifts under focus. On a remote player
  (the TV app) the page starts no gamepad source, so the row draws the
  Key slot alone (`gamepad={false}`): a Pad keycap there could capture
  nothing.

  ## Navigation

  The row is the nav item and its four controls are its
  `data-nav-sub-item`s, so the binding table is a tree: UP and DOWN walk
  rows, RIGHT steps into a row's controls and LEFT back out. SELECT on
  the row itself rebinds the key — the row is the control, as the toggle
  row is — and a click anywhere on it does the same.

  ## Glossary

  - **binding** — one action's key and gamepad button (`Controls.Binding`).
  - **slot** — one of a binding's two values; its `kind` is `:keyboard`
    or `:gamepad`.
  - **keycap** — the drawing of a slot's value, and the button that
    rebinds it. Its glyph is the host's: `ControlsLogic.display_key/1`,
    `display_button/2`.
  - **listening** — the state between pressing a keycap and the next key
    or button; `Controls.Bridge` captures it and pushes the bind.
  - **unbind** — leaving a slot empty. Not "clear": the Clear action is
    itself a binding on this page.
  """

  use MediaCentaurWeb, :html

  attr :id, :atom, required: true, doc: "the binding id; the row's DOM id is `binding-<id>`."
  attr :name, :string, required: true
  attr :description, :string, required: true
  attr :key_glyph, :string, default: nil, doc: "the key, display-formatted; nil when unbound."

  attr :button_glyph, :string,
    default: nil,
    doc: "the gamepad button under the chosen glyph style; nil when unbound."

  attr :listening, :atom,
    default: nil,
    values: [nil, :keyboard, :gamepad],
    doc: "the slot waiting for its next key or button, if any."

  attr :listen_event, :string, required: true, doc: "pushed with `id` and `kind`."
  attr :unbind_event, :string, required: true, doc: "pushed with `id` and `kind`."

  attr :gamepad, :boolean,
    default: true,
    doc: "whether the Pad slot is drawn; false on a remote player, whose page starts no gamepad source."

  def binding_row(assigns) do
    ~H"""
    <div
      id={"binding-#{@id}"}
      class={[
        "flex flex-wrap items-center justify-between py-2.5 px-3.5 gap-x-4 gap-y-2 rounded-lg",
        "cursor-pointer transition-colors duration-150 hover:bg-base-content/[0.04]",
        @listening && "bg-primary/5"
      ]}
      data-nav-item
      tabindex="0"
      data-listening={@listening}
      phx-click={@listen_event}
      phx-value-id={@id}
      phx-value-kind="keyboard"
    >
      <div class="min-w-0 grow basis-64">
        <span class="font-medium">{@name}</span>
        <p class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <div class="flex items-center gap-x-4 shrink-0" role="group" aria-label={"#{@name} bindings"}>
        <.binding_slot
          kind={:keyboard}
          id={@id}
          name={@name}
          glyph={@key_glyph}
          listening={@listening == :keyboard}
          listen_event={@listen_event}
          unbind_event={@unbind_event}
        />
        <.binding_slot
          :if={@gamepad}
          kind={:gamepad}
          id={@id}
          name={@name}
          glyph={@button_glyph}
          listening={@listening == :gamepad}
          listen_event={@listen_event}
          unbind_event={@unbind_event}
        />
      </div>
      <p :if={@listening} class="basis-full text-xs text-primary" role="status">
        Press {if @listening == :keyboard, do: "a key", else: "a button"} to bind {@name}
        <span class="text-base-content/55 ml-2">Esc to cancel</span>
      </p>
    </div>
    """
  end

  attr :kind, :atom, required: true, values: [:keyboard, :gamepad]
  attr :id, :atom, required: true
  attr :name, :string, required: true
  attr :glyph, :string, default: nil
  attr :listening, :boolean, required: true
  attr :listen_event, :string, required: true
  attr :unbind_event, :string, required: true

  # One slot: the Key or Pad label, the keycap that rebinds it, and Unbind.
  defp binding_slot(assigns) do
    assigns = assign(assigns, :word, if(assigns.kind == :keyboard, do: "key", else: "button"))

    ~H"""
    <span class="inline-flex items-center gap-1.5">
      <span class="keycap-label">{if @kind == :keyboard, do: "Key", else: "Pad"}</span>
      <button
        type="button"
        class={["keycap", is_nil(@glyph) && "keycap-unbound", @listening && "keycap-listening"]}
        data-nav-sub-item
        phx-click={@listen_event}
        phx-value-id={@id}
        phx-value-kind={@kind}
        aria-label={"Rebind the #{@word} for #{@name}"}
        data-tip="Press to rebind"
      >
        {cond do
          @listening -> "press…"
          is_nil(@glyph) -> "unbound"
          true -> @glyph
        end}
      </button>
      <.button
        variant="dismiss"
        size="xs"
        shape="square"
        class={is_nil(@glyph) && "opacity-30"}
        data-nav-sub-item
        phx-click={@glyph && @unbind_event}
        phx-value-id={@id}
        phx-value-kind={@kind}
        aria-label={"Unbind the #{@word} for #{@name}"}
        aria-disabled={is_nil(@glyph) && "true"}
        data-tip="Unbind"
      >
        <.icon name="hero-x-mark-mini" class="size-3.5" />
      </.button>
    </span>
    """
  end
end
