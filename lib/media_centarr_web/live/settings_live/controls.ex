defmodule MediaCentarrWeb.SettingsLive.Controls do
  @moduledoc """
  The Controls section of the Settings page.

  Renders the full binding table grouped by category. The parent
  `SettingsLive` delegates to `render/1` and hosts the event handlers
  that call into `MediaCentarr.Controls`.
  """

  use MediaCentarrWeb, :html

  alias MediaCentarrWeb.SettingsLive.ControlsLogic

  attr :bindings, :map, required: true
  attr :glyph_style, :string, required: true
  attr :listening, :any, required: true, doc: "{kind, id} tuple or nil"

  def render(assigns) do
    assigns = assign(assigns, :groups, ControlsLogic.group_for_view(assigns.bindings))

    ~H"""
    <div data-page="controls" class="controls-page max-w-4xl">
      <div class="flex items-end justify-between mb-2">
        <div>
          <h2 class="text-2xl font-semibold">Controls</h2>
          <p class="text-base-content/60 mt-1">Customize keyboard and gamepad bindings.</p>
        </div>
        <.button
          variant="dismiss"
          size="sm"
          phx-click="controls:reset_all"
          data-nav-item
          tabindex="0"
        >
          Reset all to defaults
        </.button>
      </div>

      <div class="flex items-center gap-2 mb-6">
        <span class="text-xs uppercase tracking-wide text-base-content/60">Glyphs:</span>
        <div class="join">
          <button
            phx-click="controls:set_glyph"
            phx-value-style="xbox"
            class={"join-item btn btn-xs " <> if(@glyph_style == "xbox", do: "btn-primary", else: "btn-ghost")}
            data-nav-item
            tabindex="0"
          >
            Xbox
          </button>
          <button
            phx-click="controls:set_glyph"
            phx-value-style="playstation"
            class={"join-item btn btn-xs " <> if(@glyph_style == "playstation", do: "btn-primary", else: "btn-ghost")}
            data-nav-item
            tabindex="0"
          >
            PlayStation
          </button>
        </div>
      </div>

      <div class="h-px bg-base-300 mb-6"></div>

      <div :for={{category, views} <- @groups} class="controls-category mb-8">
        <div class="flex items-baseline justify-between mb-3 pb-2 border-b border-dashed border-base-300">
          <h3 class="text-lg font-semibold">
            {ControlsLogic.category_label(category)}
            <span class="text-xs text-base-content/60 ml-2 uppercase tracking-wide">
              {length(views)} bindings
            </span>
          </h3>
          <button
            phx-click="controls:reset_category"
            phx-value-category={Atom.to_string(category)}
            class="text-xs text-base-content/60 hover:text-primary"
            data-nav-item
            tabindex="0"
          >
            Reset {ControlsLogic.category_label(category)}
          </button>
        </div>

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
      </div>
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
