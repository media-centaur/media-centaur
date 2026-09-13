defmodule MediaCentaurWeb.SettingsLive.Tmdb do
  @moduledoc """
  The TMDB section of the Settings page: one card, one connection row
  (UIDR-041). `SettingsLive` builds the row and hosts the row's events.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.SettingsLive.AcquisitionSection, only: [integration_row: 1]

  alias MediaCentaurWeb.SettingsLive.ConnectionState

  attr :config, :map, required: true, doc: "settings config map (reads :tmdb_api_key_configured?)."
  attr :row, ConnectionState, required: true
  attr :editing, :boolean, required: true

  def render(assigns) do
    ~H"""
    <.settings_card title="TMDB">
      <ul>
        <.integration_row
          row={@row}
          name="The Movie Database"
          editing={@editing}
          description="Metadata and artwork for everything in the library."
        >
          <:form>
            <.settings_field label="API key" layout={:stacked}>
              <.settings_input
                type="password"
                name="tmdb_api_key"
                autocomplete="off"
                mono
                autofocus
                placeholder={
                  if @config[:tmdb_api_key_configured?],
                    do: "Leave blank to keep the current key",
                    else: "Enter the API key"
                }
              />
              <p class="mt-1 text-xs text-base-content/55">
                Free at <a
                  href="https://www.themoviedb.org/settings/api"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="link link-primary"
                >themoviedb.org/settings/api</a>.
              </p>
            </.settings_field>
          </:form>
        </.integration_row>
      </ul>
    </.settings_card>
    """
  end
end
