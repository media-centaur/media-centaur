defmodule MediaCentaurWeb.SettingsLive.AcquisitionSection do
  @moduledoc """
  The Acquisition section of the Settings page (UIDR-041): five cards.
  Search holds the Prowlarr connection row; Download clients the torrent
  and usenet rows with Detect from Prowlarr on the card; Download button
  and Auto-acquisition are gated on Prowlarr's readiness and say so while
  they wait; Release tracking is one stepper. Each row is a
  `ConnectionState` built by `SettingsLive`, which owns `editing` and
  hosts every event this module names. `integration_row/1` is public
  because the TMDB section renders the same row.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings
  import MediaCentaurWeb.Components.Settings.ConnectionRow

  alias MediaCentaur.Acquisition.AutoGrabSettings
  alias MediaCentaur.Settings.Ladder
  alias MediaCentaur.Settings.Preferences.PlanningMode
  alias MediaCentaurWeb.Components.Title.Logic
  alias MediaCentaurWeb.SettingsLive.ConnectionState

  attr :config, :map,
    required: true,
    doc: "settings config map (addresses and credential presence flags)."

  attr :editing, :atom, default: nil, doc: "the connection whose form is open, or nil."

  attr :rows, :map,
    required: true,
    doc: "`%{id => ConnectionState.t()}` for :prowlarr, :download_client, :usenet_download_client."

  attr :prowlarr_configured, :boolean, required: true
  attr :prowlarr_ready, :boolean, required: true
  attr :download_client_detecting, :boolean, required: true
  attr :auto_grab, AutoGrabSettings, required: true

  attr :planning_mode, :atom,
    required: true,
    values: [:manually_select_release, :auto_select_best_release],
    doc: "the Download button's default planning mode (`Settings.Preferences.PlanningMode`)"

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <.settings_card title="Search">
        <ul>
          <.integration_row
            row={@rows.prowlarr}
            name="Prowlarr"
            editing={@editing == :prowlarr}
            description="Searches your indexers and forwards each grab to a download client."
          >
            <:form>
              <.settings_field label="Address" layout={:stacked}>
                <.settings_input
                  name="prowlarr_url"
                  value={@config[:prowlarr_url]}
                  placeholder="http://localhost:9696"
                  mono
                  autofocus
                />
              </.settings_field>
              <.settings_field
                label="API key"
                description="Prowlarr → Settings → General → Security → API Key."
                layout={:stacked}
              >
                <.settings_input
                  type="password"
                  name="prowlarr_api_key"
                  autocomplete="off"
                  mono
                  placeholder={secret_placeholder(@config[:prowlarr_api_key_configured?], "key")}
                />
              </.settings_field>
            </:form>
          </.integration_row>
        </ul>
      </.settings_card>

      <.settings_card
        title="Download clients"
        description="One client per protocol. Prowlarr sends each grab to the client that matches the indexer."
      >
        <:action>
          <.button
            id="detect-download-clients"
            variant="dismiss"
            size="xs"
            phx-click="detect_download_client"
            disabled={@download_client_detecting || !@prowlarr_configured}
            title={if !@prowlarr_configured, do: "Needs Prowlarr"}
            data-nav-item
            tabindex="0"
          >
            <span :if={@download_client_detecting} class="loading loading-spinner loading-xs"></span>
            <.icon
              :if={!@download_client_detecting}
              name="hero-magnifying-glass-mini"
              class="size-3.5"
            />
            {if @download_client_detecting, do: "Detecting…", else: "Detect from Prowlarr"}
          </.button>
        </:action>
        <ul>
          <.integration_row
            row={@rows.download_client}
            name={
              if @rows.download_client.state == :not_configured,
                do: "Torrent client",
                else: "qBittorrent"
            }
            kind="torrent"
            editing={@editing == :download_client}
            removable
            description="qBittorrent. Also powers the download progress on Incoming."
          >
            <:form>
              <div class="flex gap-3">
                <.settings_field label="Client" layout={:stacked} class="w-44 shrink-0">
                  <select
                    name="download_client_type"
                    class="select select-bordered w-full text-sm"
                    data-nav-item
                    tabindex="0"
                  >
                    <option value="qbittorrent" selected>qBittorrent</option>
                  </select>
                </.settings_field>
                <.settings_field
                  label="Address"
                  layout={:stacked}
                  class="min-w-0 flex-1"
                  description="Must be reachable from this machine. A detected address is often a hostname that only resolves inside Docker."
                >
                  <.settings_input
                    name="download_client_url"
                    value={@rows.download_client.prefill[:url] || @config[:download_client_url]}
                    placeholder="http://localhost:8080"
                    mono
                    autofocus
                  />
                </.settings_field>
              </div>
              <div class="grid grid-cols-2 gap-3">
                <.settings_field label="Username" layout={:stacked}>
                  <.settings_input
                    name="download_client_username"
                    value={
                      @rows.download_client.prefill[:username] || @config[:download_client_username]
                    }
                    placeholder="admin"
                    autocomplete="off"
                    mono
                  />
                </.settings_field>
                <.settings_field label="Password" layout={:stacked}>
                  <.settings_input
                    type="password"
                    name="download_client_password"
                    autocomplete="off"
                    mono
                    placeholder={
                      secret_placeholder(@config[:download_client_password_configured?], "password")
                    }
                  />
                </.settings_field>
              </div>
            </:form>
          </.integration_row>

          <.integration_row
            row={@rows.usenet_download_client}
            name={
              if @rows.usenet_download_client.state == :not_configured,
                do: "Usenet client",
                else: "SABnzbd"
            }
            kind="usenet"
            editing={@editing == :usenet_download_client}
            removable
            description="SABnzbd. Repairs and unpacks; the finished file imports like any other download."
          >
            <:form>
              <div class="flex gap-3">
                <.settings_field label="Client" layout={:stacked} class="w-44 shrink-0">
                  <select
                    name="usenet_download_client_type"
                    class="select select-bordered w-full text-sm"
                    data-nav-item
                    tabindex="0"
                  >
                    <option value="sabnzbd" selected>SABnzbd</option>
                  </select>
                </.settings_field>
                <.settings_field
                  label="Address"
                  layout={:stacked}
                  class="min-w-0 flex-1"
                  description="Must be reachable from this machine. A detected address is often a hostname that only resolves inside Docker."
                >
                  <.settings_input
                    name="usenet_download_client_url"
                    value={
                      @rows.usenet_download_client.prefill[:url] ||
                        @config[:usenet_download_client_url]
                    }
                    placeholder="http://localhost:8085"
                    mono
                    autofocus
                  />
                </.settings_field>
              </div>
              <.settings_field
                label="API key"
                description="SABnzbd → Config → General → API Key."
                layout={:stacked}
              >
                <.settings_input
                  type="password"
                  name="usenet_download_client_api_key"
                  autocomplete="off"
                  mono
                  placeholder={
                    secret_placeholder(@config[:usenet_download_client_api_key_configured?], "key")
                  }
                />
              </.settings_field>
            </:form>
          </.integration_row>
        </ul>
      </.settings_card>

      <.settings_card id="card-download-button" title="Download button">
        <.gate :if={!@prowlarr_ready} />
        <.settings_choice
          :if={@prowlarr_ready}
          id="planning-mode"
          label="Default action on a title you don't own yet"
          description="The other choice stays in the button's menu."
          options={
            for mode <- PlanningMode.modes(),
                do: {Atom.to_string(mode), Logic.planning_mode_label(mode)}
          }
          selected={Atom.to_string(@planning_mode)}
          event="set_planning_mode"
        />
      </.settings_card>

      <.settings_card
        id="card-auto-acquisition"
        title="Auto-acquisition"
        description={
          @prowlarr_ready &&
            "Applied when a tracked title's release appears. A title's own tracking controls take precedence."
        }
      >
        <.gate :if={!@prowlarr_ready} />
        <div :if={@prowlarr_ready} class="space-y-0.5">
          <.settings_choice
            id="auto-grab-default_mode"
            label="When a release appears"
            description="Ask first parks the plan on Incoming until you approve it."
            options={[{"all_releases", "Grab it"}, {"ask", "Ask first"}, {"off", "Notify only"}]}
            selected={@auto_grab.default_mode}
            event="set_auto_grab"
            event_value={%{"key" => "default_mode"}}
          />
          <.settings_choice
            id="auto-grab-default_max_quality"
            label="Highest resolution"
            description="The best available is taken right away. Nothing found at this resolution falls back to 1080p; anything lower needs the title's own acceptance."
            options={[{"uhd_4k", "4K"}, {"hd_1080p", "1080p"}]}
            selected={@auto_grab.default_max_quality}
            event="set_auto_grab"
            event_value={%{"key" => "default_max_quality"}}
          />
          <.settings_choice
            id="auto-grab-size_preference"
            label="Within a resolution"
            description="Best fidelity takes a remux first. Save space takes compact encodes first, and still takes a remux when nothing smaller exists."
            options={[{"fidelity", "Best fidelity"}, {"space", "Save space"}]}
            selected={@auto_grab.size_preference}
            event="set_auto_grab"
            event_value={%{"key" => "size_preference"}}
          />
          <.settings_stepper
            id="auto-grab-pack_min_fit"
            label="Season packs"
            description="Take a pack only when you want at least this share of its episodes. Below it, episodes are grabbed one by one and the pack is offered."
            value_label={"#{@auto_grab.pack_min_fit}%"}
            down_value={Ladder.down(AutoGrabSettings.pack_fit_ladder(), @auto_grab.pack_min_fit)}
            up_value={Ladder.up(AutoGrabSettings.pack_fit_ladder(), @auto_grab.pack_min_fit)}
            reset_value={75}
            at_min={@auto_grab.pack_min_fit <= 5}
            at_max={@auto_grab.pack_min_fit >= 100}
            at_default={@auto_grab.pack_min_fit == 75}
            event="set_auto_grab"
            event_value={%{"key" => "pack_min_fit"}}
          />
          <.settings_stepper
            id="auto-grab-max_attempts"
            label="Search attempts"
            description="Failed search cycles before a release is given up on."
            value_label={Integer.to_string(@auto_grab.max_attempts)}
            down_value={Ladder.down(AutoGrabSettings.attempts_ladder(), @auto_grab.max_attempts)}
            up_value={Ladder.up(AutoGrabSettings.attempts_ladder(), @auto_grab.max_attempts)}
            reset_value={12}
            at_min={@auto_grab.max_attempts <= 1}
            at_max={@auto_grab.max_attempts >= 50}
            at_default={@auto_grab.max_attempts == 12}
            event="set_auto_grab"
            event_value={%{"key" => "max_attempts"}}
          />
        </div>
      </.settings_card>

      <.settings_card title="Release tracking">
        <.settings_stepper
          id="release-tracking-interval"
          label="Check TMDB for new release dates"
          description="How often, in hours. A change applies after the current cycle finishes."
          value_label={"#{refresh_hours(@config)}h"}
          down_value={Ladder.down(refresh_ladder(), refresh_hours(@config))}
          up_value={Ladder.up(refresh_ladder(), refresh_hours(@config))}
          reset_value={6}
          at_min={refresh_hours(@config) <= 1}
          at_max={refresh_hours(@config) >= 24}
          at_default={refresh_hours(@config) == 6}
          event="set_release_tracking_interval"
        />
      </.settings_card>
    </div>
    """
  end

  # The stepper's rungs for the TMDB refresh interval, in hours. A
  # function, not an attribute: inside ~H `@name` is an assign.
  defp refresh_ladder, do: [1, 2, 3, 4, 6, 8, 12, 24]

  defp refresh_hours(config), do: config[:release_tracking_refresh_interval_hours] || 6

  defp secret_placeholder(true, noun), do: "Leave blank to keep the current #{noun}"
  defp secret_placeholder(_stored, "key"), do: "Enter the API key"
  defp secret_placeholder(_stored, "password"), do: "Enter the password"

  # The one line a gated card shows while Prowlarr is not ready (UIDR-041 §4).
  defp gate(assigns) do
    ~H"""
    <p class="text-sm text-base-content/60">Available once Prowlarr's connection test passes.</p>
    """
  end

  attr :row, ConnectionState, required: true
  attr :name, :string, required: true
  attr :kind, :string, default: nil
  attr :editing, :boolean, required: true
  attr :removable, :boolean, default: false, doc: "a client slot: the form offers Remove client."

  attr :description, :string,
    required: true,
    doc: "shown on the detail line while nothing is configured."

  slot :form, required: true, doc: "the connection's fields; the footer is this component's."

  @doc """
  A connection row for one integration: the readout's actions per state
  and the edit form with its footer (Cancel, Save and test, Save; Remove
  client for a slot). Events: `edit_connection`, `test_connection`,
  `review_detected`, `dismiss_detected`, `cancel_edit`, `remove_client`,
  and the form's `save_connection` with `_action` save or test.
  """
  def integration_row(assigns) do
    assigns = assign(assigns, :id, Atom.to_string(assigns.row.id))

    ~H"""
    <.connection_row
      id={"connection-#{@id}"}
      name={@name}
      kind={@kind}
      state={@row.state}
      state_label={@row.state_label}
      tested_at={@row.tested_at}
      address={if @row.state != :not_configured, do: @row.address}
      detail={if @row.state == :not_configured, do: @description, else: @row.credential}
      editing={@editing}
    >
      <:actions>
        <%= case @row.state do %>
          <% :not_configured -> %>
            <.button
              id={"connection-#{@id}-setup"}
              variant="secondary"
              size="xs"
              phx-click="edit_connection"
              phx-value-connection={@id}
              data-nav-item
              tabindex="0"
            >
              Set up
            </.button>
          <% :detected -> %>
            <.button
              id={"connection-#{@id}-review"}
              variant="secondary"
              size="xs"
              phx-click="review_detected"
              phx-value-connection={@id}
              data-nav-item
              tabindex="0"
            >
              Review
            </.button>
            <.button
              id={"connection-#{@id}-dismiss"}
              variant="dismiss"
              size="xs"
              phx-click="dismiss_detected"
              phx-value-connection={@id}
              data-nav-item
              tabindex="0"
            >
              Dismiss
            </.button>
          <% _configured -> %>
            <.button
              id={"connection-#{@id}-test"}
              variant="neutral"
              size="xs"
              phx-click="test_connection"
              phx-value-connection={@id}
              disabled={@row.state == :pending}
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-signal-mini" class="size-3.5" /> Test
            </.button>
            <.button
              id={"connection-#{@id}-edit"}
              variant="dismiss"
              size="xs"
              phx-click="edit_connection"
              phx-value-connection={@id}
              data-nav-item
              tabindex="0"
            >
              Edit
            </.button>
        <% end %>
      </:actions>
      <:edit>
        <form id={"connection-#{@id}-form"} phx-submit="save_connection" class="space-y-4">
          <input type="hidden" name="connection" value={@id} />
          {render_slot(@form)}
          <div class="flex items-center justify-between gap-3 pt-1">
            <div>
              <.button
                :if={@removable}
                id={"connection-#{@id}-remove"}
                variant="destructive_inline"
                size="sm"
                type="button"
                phx-click="remove_client"
                phx-value-connection={@id}
                data-nav-item
                tabindex="0"
              >
                Remove client
              </.button>
            </div>
            <div class="flex items-center gap-2">
              <.button
                id={"connection-#{@id}-cancel"}
                variant="dismiss"
                size="sm"
                type="button"
                phx-click="cancel_edit"
                data-nav-item
                tabindex="0"
              >
                Cancel
              </.button>
              <.button
                type="submit"
                variant="neutral"
                size="sm"
                name="_action"
                value="test"
                disabled={@row.state == :pending}
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-signal-mini" class="size-4" /> Save and test
              </.button>
              <.button
                type="submit"
                variant="secondary"
                size="sm"
                name="_action"
                value="save"
                data-nav-item
                tabindex="0"
              >
                Save
              </.button>
            </div>
          </div>
        </form>
      </:edit>
    </.connection_row>
    """
  end
end
