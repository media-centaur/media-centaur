defmodule MediaCentaurWeb.SettingsLive.Controls do
  @moduledoc """
  The Controls section of the Settings page.

  Renders the full binding table grouped by category. The parent
  `SettingsLive` delegates to `render/1` and hosts the event handlers
  that call into `MediaCentaur.Settings.Controls`.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaurWeb.SettingsLive.ControlsLogic

  attr :bindings, :map,
    required: true,
    doc:
      "the full bindings map keyed by binding id — value is a `MediaCentaur.Settings.Controls.Binding.t()`. Produced by `MediaCentaur.Settings.Controls.list_bindings/0` and grouped via `ControlsLogic.group_for_view/1`."

  attr :glyph_style, :string, required: true
  attr :listening, :any, required: true, doc: "{kind, id} tuple or nil"
  attr :reset_armed, :boolean, default: false, doc: "Reset all is one click from firing."

  def render(assigns) do
    assigns = assign(assigns, :groups, ControlsLogic.group_for_view(assigns.bindings))

    ~H"""
    <div data-page="controls" class="controls-page max-w-4xl">
      <div class="flex justify-end mb-2">
        <.armed_button
          armed={@reset_armed}
          arm="controls:reset_all_arm"
          fire="controls:reset_all"
          armed_label="Click again to reset every binding"
          variant="dismiss"
        >
          Reset all to defaults
        </.armed_button>
      </div>

      <.settings_card title="Gamepad glyphs" class="mb-4">
        <.settings_choice
          label="Button glyphs"
          description="How gamepad buttons are drawn in the bindings below."
          options={[{"xbox", "Xbox"}, {"playstation", "PlayStation"}]}
          selected={@glyph_style}
          event="controls:set_glyph"
        />
      </.settings_card>

      <.settings_card
        :for={{category, views} <- @groups}
        title={ControlsLogic.category_label(category)}
        class="controls-category mb-4"
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

        <div class="controls-list">
          <div
            :for={view <- views}
            class="controls-row"
            data-listening={if listening?(@listening, view.id), do: "true", else: "false"}
          >
            <div class="controls-row-label">
              <div class="font-semibold">{view.name}</div>
              <div class="text-sm text-base-content/60">{view.description}</div>
            </div>

            <div class="controls-row-slots">
              <.slot_view
                kind={:keyboard}
                id={view.id}
                glyph={ControlsLogic.display_key(view.key)}
                listening={listening_slot?(@listening, view.id, :keyboard)}
              />

              <.slot_view
                kind={:gamepad}
                id={view.id}
                glyph={ControlsLogic.display_button(view.button, @glyph_style)}
                listening={listening_slot?(@listening, view.id, :gamepad)}
                gamepad_available={false}
              />
            </div>

            <div class="controls-row-actions">
              <button
                phx-click="controls:listen"
                phx-value-id={Atom.to_string(view.id)}
                phx-value-kind="keyboard"
                class="controls-icon-btn"
                title="Remap key"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-pencil" class="w-4 h-4" />
              </button>
              <button
                phx-click="controls:clear"
                phx-value-id={Atom.to_string(view.id)}
                phx-value-kind="keyboard"
                class="controls-icon-btn danger"
                title="Clear key"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-x-mark" class="w-4 h-4" />
              </button>
            </div>

            <div :if={listening?(@listening, view.id)} class="controls-listen-hint">
              Press any key to bind {view.name}
              <span class="text-base-content/60 ml-3">Esc to cancel</span>
            </div>
          </div>
        </div>
      </.settings_card>
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :id, :atom, required: true
  attr :glyph, :string, default: nil
  attr :listening, :boolean, default: false
  attr :gamepad_available, :boolean, default: true

  defp slot_view(assigns) do
    ~H"""
    <div class={"controls-slot controls-slot-#{@kind}"}>
      <span class="controls-slot-label">{if @kind == :keyboard, do: "Key", else: "Pad"}</span>
      <span class={"controls-keycap " <>
        if(@listening, do: "listening ", else: "") <>
        if(is_nil(@glyph), do: "empty", else: "")}>
        {cond do
          @listening -> "press…"
          is_nil(@glyph) -> "unset"
          true -> @glyph
        end}
      </span>
    </div>
    """
  end

  defp listening?(nil, _), do: false
  defp listening?({_kind, id}, id), do: true
  defp listening?(_, _), do: false

  defp listening_slot?(nil, _, _), do: false
  defp listening_slot?({kind, id}, id, kind), do: true
  defp listening_slot?(_, _, _), do: false
end
