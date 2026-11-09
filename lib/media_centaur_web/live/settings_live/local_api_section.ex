defmodule MediaCentaurWeb.SettingsLive.LocalApiSection do
  @moduledoc """
  The Local API section of the Settings page: the API key, shown only in
  the moment it is generated, and the addresses a caller uses.
  `SettingsLive` delegates to `render/1` and hosts `generate_api_key`.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaurWeb.Live.ArmGesture
  alias MediaCentaurWeb.SettingsLive.Reach

  attr :api_key, :string, required: true, doc: "the key just generated, or nil"
  attr :api_key_exists?, :boolean, required: true
  attr :reach, :any, required: true, doc: "`Reach.reach/2`'s answer"
  attr :armed_gesture, :any, required: true, doc: "the page's `ArmGesture` slot"

  def render(assigns) do
    ~H"""
    <div id="settings-local-api" class="space-y-4">
      <.settings_card
        id="local-api-key-card"
        title="API key"
        description="Send it with every request, as the header Authorization: Bearer <key>."
      >
        <:action :if={@api_key_exists?}>
          <.armed_button
            id="replace-api-key"
            event="generate_api_key"
            variant="risky"
            armed={ArmGesture.armed?(@armed_gesture, "generate_api_key", "key")}
            armed_label="Press again to replace"
          >
            Replace key
          </.armed_button>
        </:action>
        <div :if={@api_key} class="px-3.5 space-y-1">
          <div id="local-api-key" class="font-mono break-all text-base-content">{@api_key}</div>
          <p class="text-warning">Copy this key now. It can't be shown again.</p>
        </div>
        <p :if={is_nil(@api_key) and @api_key_exists?} class="px-3.5 text-base-content/70">
          If the key is lost, replace it. Anything using the old key stops working.
        </p>
        <div :if={not @api_key_exists?} class="px-3.5 space-y-3">
          <p class="text-base-content/70">Every request is refused until a key exists.</p>
          <.button
            id="generate-api-key"
            variant="neutral"
            size="sm"
            phx-click="generate_api_key"
            data-nav-item
            tabindex="0"
          >
            Generate key
          </.button>
        </div>
      </.settings_card>

      <.settings_card id="local-api-address" title="Address">
        <div class="px-3.5 space-y-2">
          <div :for={url <- Reach.addresses(@reach)} class="font-mono text-base-content/80">
            {url}/api/v1
          </div>
          <p :if={@reach == :loopback} class="text-warning">
            Only this computer can reach the API: it listens on 127.0.0.1. For other devices, set
            <code class="font-mono">bind = "0.0.0.0"</code>
            in the config file and restart the service.
          </p>
          <p class="text-base-content/70">
            The API's OpenAPI document is at <code class="font-mono">/api/v1/openapi.json</code>
            and needs the key. Give it to your agent or API client.
          </p>
          <p class="text-base-content/70">
            Requests use plain HTTP, so the key is readable by anyone who can capture traffic on your network.
          </p>
        </div>
      </.settings_card>
    </div>
    """
  end
end
