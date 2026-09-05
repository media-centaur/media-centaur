defmodule MediaCentaurWeb.SettingsLive.Tmdb do
  @moduledoc """
  The TMDB section of the Settings page — API key and connection test.
  `SettingsLive` delegates to `render/1` and hosts the save / test handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  attr :config, :map,
    required: true,
    doc: "settings config map (reads :tmdb_api_key_configured?)."

  attr :tmdb_test, :any, required: true, doc: "connection-test result map or nil."
  attr :tmdb_testing, :boolean, required: true

  def render(assigns) do
    ~H"""
    <form id="settings-tmdb" phx-submit="save_tmdb" class="p-5 rounded-lg glass-surface space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold flex items-center gap-2">
            TMDB <.status_dot configured={@config[:tmdb_api_key_configured?]} />
          </h2>
          <p class="text-sm text-base-content/55 mt-0.5">
            The Movie Database API — required for metadata scraping and artwork.
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
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/55 block mb-1.5">
            API Key
          </label>
          <input
            type="password"
            name="tmdb_api_key"
            class="input input-bordered w-full font-mono text-sm"
            placeholder={
              if @config[:tmdb_api_key_configured?],
                do: "Leave blank to keep current key",
                else: "Enter your TMDB API key"
            }
            autocomplete="off"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/55 mt-1">
            Don't have one yet? Request a free key at <a
              href="https://www.themoviedb.org/settings/api"
              target="_blank"
              rel="noopener noreferrer"
              class="link link-primary"
            >themoviedb.org/settings/api</a>.
          </p>
        </div>
      </div>

      <div class="pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
        <.connection_status
          test={@tmdb_test}
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
          disabled={@tmdb_testing}
          data-nav-item
          tabindex="0"
        >
          <span :if={@tmdb_testing} class="loading loading-spinner loading-xs"></span>
          <.icon :if={!@tmdb_testing} name="hero-signal-mini" class="size-4" />
          {if @tmdb_testing, do: "Testing…", else: "Test connection"}
        </.button>
      </div>
    </form>
    """
  end
end
