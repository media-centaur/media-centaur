defmodule MediaCentaurWeb.SettingsLive.AcquisitionSection do
  @moduledoc """
  The Acquisition section of the Settings page — Prowlarr + download-client
  configuration (with connection tests / detect-from-Prowlarr) and the
  auto-grab defaults form. `SettingsLive` computes the capability/display
  values and delegates to `render/1`; it hosts the save / test / detect
  handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  attr :config, :map, required: true, doc: "settings config map (prowlarr/download-client keys)."
  attr :prowlarr_configured, :boolean, required: true
  attr :prowlarr_ready, :boolean, required: true
  attr :prowlarr_test, :any, required: true, doc: "connection-test result map or nil."
  attr :prowlarr_testing, :boolean, required: true

  attr :download_client_display, :map,
    required: true,
    doc: "torrent client type/url/username for the form (pending detect or persisted)."

  attr :download_client_detecting, :boolean, required: true
  attr :download_client_test, :any, required: true, doc: "connection-test result map or nil."
  attr :download_client_testing, :boolean, required: true

  attr :usenet_client_display, :map,
    required: true,
    doc: "usenet client type/url for the form (pending detect or persisted)."

  attr :usenet_client_test, :any, required: true, doc: "connection-test result map or nil."
  attr :usenet_client_testing, :boolean, required: true
  attr :auto_grab, :map, required: true, doc: "AutoGrabSettings map (default_mode, patience_hours)."

  def render(assigns) do
    ~H"""
    <div class="space-y-5">
      <form
        id="settings-prowlarr"
        phx-submit="save_prowlarr"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              Prowlarr <.status_dot configured={@config[:prowlarr_api_key_configured?]} />
            </h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Indexer proxy that searches for media and forwards grabs.
            </p>
          </div>
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
        </div>

        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              URL
            </label>
            <input
              type="text"
              name="prowlarr_url"
              value={@config[:prowlarr_url]}
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              API Key
            </label>
            <input
              type="password"
              name="prowlarr_api_key"
              class="input input-bordered w-full font-mono text-sm"
              placeholder={
                if @config[:prowlarr_api_key_configured?],
                  do: "Leave blank to keep current key",
                  else: "Enter your Prowlarr API key"
              }
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
          </div>
        </div>

        <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <.connection_status
            test={@prowlarr_test}
            ok_label="Connected"
            error_label="Unreachable"
          />
          <.button
            type="submit"
            variant="neutral"
            size="sm"
            class="shrink-0"
            name="_action"
            value="test"
            disabled={@prowlarr_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@prowlarr_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@prowlarr_testing} name="hero-signal-mini" class="size-4" />
            {if @prowlarr_testing, do: "Testing…", else: "Test connection"}
          </.button>
        </div>
      </form>

      <form
        id="settings-download-client"
        phx-submit="save_download_client"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              Torrent Client
              <.status_dot configured={@config[:download_client_password_configured?]} />
            </h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Where Prowlarr forwards torrent grabs. Powers the Downloads page progress.
            </p>
          </div>
          <div class="flex flex-wrap gap-2 shrink-0">
            <.button
              variant="neutral"
              size="sm"
              phx-click="detect_download_client"
              disabled={@download_client_detecting || !@prowlarr_configured}
              data-nav-item
              tabindex="0"
            >
              <span :if={@download_client_detecting} class="loading loading-spinner loading-xs">
              </span>
              <.icon
                :if={!@download_client_detecting}
                name="hero-magnifying-glass-mini"
                class="size-4"
              />
              {if @download_client_detecting, do: "Detecting…", else: "Detect"}
            </.button>
            <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
              Save
            </.button>
          </div>
        </div>

        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Type
            </label>
            <select
              name="download_client_type"
              class="select select-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            >
              <option value="" selected={@download_client_display.type in [nil, ""]}>
                Not configured
              </option>
              <option
                value="qbittorrent"
                selected={@download_client_display.type == "qbittorrent"}
              >
                qBittorrent
              </option>
            </select>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              URL
            </label>
            <input
              type="text"
              name="download_client_url"
              value={@download_client_display.url}
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Must be reachable from <em>this</em>
              machine. If you used <span class="font-mono">Detect from Prowlarr</span>, verify the URL —
              Prowlarr often returns Docker-internal hostnames (<span class="font-mono">qbittorrent:8080</span>)
              that only resolve inside the container network.
            </p>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Username
              </label>
              <input
                type="text"
                name="download_client_username"
                value={@download_client_display.username}
                class="input input-bordered w-full font-mono text-sm"
                placeholder="admin"
                autocomplete="off"
                data-nav-item
                tabindex="0"
              />
            </div>

            <div>
              <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
                Password
              </label>
              <input
                type="password"
                name="download_client_password"
                class="input input-bordered w-full font-mono text-sm"
                placeholder={
                  if @config[:download_client_password_configured?],
                    do: "Leave blank to keep current",
                    else: "Enter password"
                }
                autocomplete="off"
                data-nav-item
                tabindex="0"
              />
            </div>
          </div>
        </div>

        <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <.connection_status
            test={@download_client_test}
            ok_label="Connected"
            error_label="Unreachable / auth failed"
          />
          <.button
            type="submit"
            variant="neutral"
            size="sm"
            class="shrink-0"
            name="_action"
            value="test"
            disabled={@download_client_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@download_client_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@download_client_testing} name="hero-signal-mini" class="size-4" />
            {if @download_client_testing, do: "Testing…", else: "Test connection"}
          </.button>
        </div>
      </form>

      <form
        id="settings-usenet-client"
        phx-submit="save_usenet_client"
        class="p-5 rounded-lg glass-surface space-y-5"
      >
        <div class="flex items-start justify-between gap-4">
          <div class="min-w-0">
            <h2 class="text-lg font-semibold flex items-center gap-2">
              Usenet Client
              <.status_dot configured={@config[:usenet_download_client_api_key_configured?]} />
            </h2>
            <p class="text-sm text-base-content/50 mt-0.5">
              Where Prowlarr forwards usenet grabs. SABnzbd repairs and unpacks;
              the finished file imports like any other download.
            </p>
          </div>
          <.button
            type="submit"
            variant="secondary"
            size="sm"
            class="shrink-0"
            data-nav-item
            tabindex="0"
          >
            Save
          </.button>
        </div>

        <div class="space-y-3">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              Type
            </label>
            <select
              name="usenet_download_client_type"
              class="select select-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            >
              <option value="" selected={@usenet_client_display.type in [nil, ""]}>
                Not configured
              </option>
              <option value="sabnzbd" selected={@usenet_client_display.type == "sabnzbd"}>
                SABnzbd
              </option>
            </select>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              URL
            </label>
            <input
              type="text"
              name="usenet_download_client_url"
              value={@usenet_client_display.url}
              class="input input-bordered w-full font-mono text-sm"
              data-nav-item
              tabindex="0"
            />
            <p class="text-xs text-base-content/40 mt-1">
              Must be reachable from <em>this</em>
              machine — Prowlarr-detected URLs are often Docker-internal hostnames.
            </p>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
              API Key
            </label>
            <input
              type="password"
              name="usenet_download_client_api_key"
              class="input input-bordered w-full font-mono text-sm"
              placeholder={
                if @config[:usenet_download_client_api_key_configured?],
                  do: "Leave blank to keep current key",
                  else: "SABnzbd → Config → General → API Key"
              }
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
          </div>
        </div>

        <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <.connection_status
            test={@usenet_client_test}
            ok_label="Connected"
            error_label="Unreachable / bad API key"
          />
          <.button
            type="submit"
            variant="neutral"
            size="sm"
            class="shrink-0"
            name="_action"
            value="test"
            disabled={@usenet_client_testing}
            data-nav-item
            tabindex="0"
          >
            <span :if={@usenet_client_testing} class="loading loading-spinner loading-xs"></span>
            <.icon :if={!@usenet_client_testing} name="hero-signal-mini" class="size-4" />
            {if @usenet_client_testing, do: "Testing…", else: "Test connection"}
          </.button>
        </div>
      </form>

      <.auto_grab_defaults_form :if={@prowlarr_ready} auto_grab={@auto_grab} />
    </div>
    """
  end

  defp auto_grab_defaults_form(assigns) do
    ~H"""
    <form
      phx-submit="save_auto_grab_defaults"
      class="p-5 rounded-lg glass-surface space-y-5"
    >
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Auto-acquisition defaults</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Applied when a tracked release becomes available. Per-item
            overrides on individual tracking entries take precedence.
          </p>
        </div>
        <.button
          type="submit"
          variant="secondary"
          size="sm"
          class="shrink-0"
          data-nav-item
          tabindex="0"
        >
          Save
        </.button>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Default mode
          </label>
          <select
            name="auto_grab[default_mode]"
            class="select select-bordered w-full"
            data-nav-item
            tabindex="0"
          >
            <option value="all_releases" selected={@auto_grab.default_mode == "all_releases"}>
              Auto-grab all releases
            </option>
            <option value="ask" selected={@auto_grab.default_mode == "ask"}>
              Ask first (plans await approval)
            </option>
            <option value="off" selected={@auto_grab.default_mode == "off"}>
              Off (notify only)
            </option>
          </select>
          <p class="text-xs text-base-content/40 mt-1">
            Applies to newly-tracked items. Existing items keep their per-item override.
          </p>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            4K patience (hours)
          </label>
          <input
            type="number"
            name="auto_grab[4k_patience_hours]"
            value={@auto_grab.patience_hours}
            min="0"
            max="720"
            class="input input-bordered w-full font-mono text-sm"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            Wait this long for a 4K release before falling back to 1080p. Set to 0 to grab immediately.
          </p>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Minimum quality (final fallback)
          </label>
          <select
            name="auto_grab[default_min_quality]"
            class="select select-bordered w-full"
            data-nav-item
            tabindex="0"
          >
            <option value="hd_1080p" selected={@auto_grab.default_min_quality == "hd_1080p"}>
              1080p
            </option>
            <option value="uhd_4k" selected={@auto_grab.default_min_quality == "uhd_4k"}>
              4K only
            </option>
          </select>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Maximum quality
          </label>
          <select
            name="auto_grab[default_max_quality]"
            class="select select-bordered w-full"
            data-nav-item
            tabindex="0"
          >
            <option value="uhd_4k" selected={@auto_grab.default_max_quality == "uhd_4k"}>
              4K
            </option>
            <option value="hd_1080p" selected={@auto_grab.default_max_quality == "hd_1080p"}>
              1080p (no 4K)
            </option>
          </select>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Maximum search attempts
          </label>
          <input
            type="number"
            name="auto_grab[max_attempts]"
            value={@auto_grab.max_attempts}
            min="1"
            max="50"
            class="input input-bordered w-full font-mono text-sm"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            How many failed search cycles before giving up on a release.
          </p>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Pack threshold (%)
          </label>
          <input
            type="number"
            name="auto_grab[pack_min_fit]"
            value={@auto_grab.pack_min_fit}
            min="1"
            max="100"
            class="input input-bordered w-full font-mono text-sm"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            Grab a season or series pack only when you want at least this share of the
            episodes it contains. Below it, picking a few episodes grabs them individually
            and the pack is offered as a one-click choice.
          </p>
        </div>
      </div>
    </form>
    """
  end
end
