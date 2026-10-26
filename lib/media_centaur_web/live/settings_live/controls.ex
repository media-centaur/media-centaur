defmodule MediaCentaurWeb.SettingsLive.Controls do
  @moduledoc """
  The Controls section of the Settings page: the binding table.

  The first card, Bindings, carries the one-line instruction for the
  gesture (press a keycap, then the key or button), Reset all on its
  title line and the gamepad glyph style. The category cards beneath it
  sit in one `bindings` nav zone — a tree whose items are the rows
  (`Components.Settings.BindingRow`) and each category's Reset, so UP and
  DOWN walk the table and RIGHT steps into a row's keycaps. The parent
  `SettingsLive` delegates to `render/1` and hosts the event handlers
  that call into `MediaCentaur.Settings.Controls`.

  On a remote player (the TV app) the page starts no gamepad source, so
  the section speaks only of keys (`gamepad={false}`): no Pad slot in a
  row, no glyph style, and the instruction names the key alone.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.BindingRow

  alias MediaCentaurWeb.SettingsLive.ControlsLogic

  attr :bindings, :map,
    required: true,
    doc:
      "the full bindings map keyed by binding id — value is a `MediaCentaur.Settings.Controls.Binding.t()`. Produced by `MediaCentaur.Settings.Controls.list_bindings/0` and grouped via `ControlsLogic.group_for_view/1`."

  attr :glyph_style, :string, required: true
  attr :listening, :any, required: true, doc: "{kind, id} tuple or nil"
  attr :reset_armed, :boolean, default: false, doc: "Reset all is one click from firing."

  attr :gamepad, :boolean,
    required: true,
    doc:
      "whether the page's player drives the UI with a gamepad: true on the host, false on a remote player."

  def render(assigns) do
    assigns = assign(assigns, :groups, ControlsLogic.group_for_view(assigns.bindings))

    ~H"""
    <div data-page="controls" class="space-y-4">
      <.settings_card
        title="Bindings"
        description={
          if @gamepad,
            do:
              "Every action has a key and a gamepad button. Press a keycap, then the key or button to put there.",
            else: "Every action has a key. Press a keycap, then the key to put there."
        }
      >
        <:action>
          <.armed_button
            armed={@reset_armed}
            event="controls:reset_all"
            armed_label="Click again to reset every binding"
            variant="dismiss"
            size="xs"
          >
            Reset all
          </.armed_button>
        </:action>
        <.settings_choice
          :if={@gamepad}
          label="Gamepad glyphs"
          description="How gamepad buttons are drawn."
          options={[{"xbox", "Xbox"}, {"playstation", "PlayStation"}]}
          selected={@glyph_style}
          event="controls:set_glyph"
        />
      </.settings_card>

      <div data-nav-zone="bindings" class="space-y-4">
        <.settings_card
          :for={{category, views} <- @groups}
          id={"controls-#{category}"}
          title={ControlsLogic.category_label(category)}
        >
          <:action>
            <.button
              variant="dismiss"
              size="xs"
              phx-click="controls:reset_category"
              phx-value-category={Atom.to_string(category)}
              data-nav-item
              tabindex="0"
            >
              Reset {ControlsLogic.category_label(category)}
            </.button>
          </:action>

          <.binding_row
            :for={view <- views}
            id={view.id}
            name={view.name}
            description={view.description}
            key_glyph={ControlsLogic.display_key(view.key)}
            button_glyph={ControlsLogic.display_button(view.button, @glyph_style)}
            listening={ControlsLogic.listening_kind(@listening, view.id)}
            listen_event="controls:listen"
            unbind_event="controls:unbind"
            gamepad={@gamepad}
          />
        </.settings_card>
      </div>
    </div>
    """
  end
end
