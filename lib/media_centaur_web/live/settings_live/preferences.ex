defmodule MediaCentaurWeb.SettingsLive.Preferences do
  @moduledoc """
  The Preferences section of the Settings page — personal display and browsing
  preferences (durable, stored in Settings). `SettingsLive` delegates to
  `render/1` and hosts the event handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.Settings.Preferences.UIScale

  attr :spoiler_free, :boolean, required: true
  attr :ui_scale, :float, required: true
  attr :show_card_info, :boolean, required: true
  attr :show_play_button, :boolean, required: true
  attr :auto_play_next_episode, :boolean, required: true
  attr :letterboxd_links, :boolean, required: true
  attr :show_discovery, :boolean, required: true
  attr :show_apps, :boolean, required: true

  def render(assigns) do
    ~H"""
    <.settings_card title="Display" data-nav-grid>
      <div class="space-y-0.5">
        <.settings_row
          label="Spoiler-free mode"
          description="Blur episode descriptions until hovered"
          checked={@spoiler_free}
          event="toggle_spoiler_free"
        />

        <.settings_row
          label="Show titles below posters"
          description="Hide for a clean wall-of-posters view"
          checked={@show_card_info}
          event="toggle_show_card_info"
        />

        <.settings_row
          label="Play button on cards"
          description="Hover a card to play it in one click"
          checked={@show_play_button}
          event="toggle_show_play_button"
        />

        <.settings_row
          label="Auto-play next episode"
          description="When an episode ends, the next one starts on its own"
          checked={@auto_play_next_episode}
          event="toggle_auto_play_next_episode"
        />

        <.settings_row
          label="Letterboxd links"
          description="Movie pages link to the film on Letterboxd"
          checked={@letterboxd_links}
          event="toggle_letterboxd_links"
        />

        <.settings_row
          label="Discovery"
          description="Show the Discovery page in the sidebar. Early preview — it may still change shape"
          checked={@show_discovery}
          event="toggle_show_discovery"
        />

        <.settings_row
          label="Apps"
          description="Show the Apps launcher in the sidebar"
          checked={@show_apps}
          event="toggle_show_apps"
        />

        <.settings_stepper
          label="Interface scale"
          description="The interface sizes itself to your screen automatically — adjust in 5% steps if you'd like it larger or smaller."
          value_label={UIScale.percent(@ui_scale)}
          down_value={UIScale.decrement(@ui_scale)}
          up_value={UIScale.increment(@ui_scale)}
          reset_value={UIScale.default()}
          at_min={@ui_scale <= UIScale.min()}
          at_max={@ui_scale >= UIScale.max()}
          at_default={@ui_scale == UIScale.default()}
          event="set_ui_scale"
        />
      </div>
    </.settings_card>
    """
  end
end
