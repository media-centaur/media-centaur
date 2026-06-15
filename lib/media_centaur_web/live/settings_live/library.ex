defmodule MediaCentaurWeb.SettingsLive.Library do
  @moduledoc """
  The Library section of the Settings page — data directory, media
  directories (add/edit/remove), excluded directories, display toggle, and
  cleanup TTLs. `SettingsLive` delegates to `render/1` and hosts the
  media_dir / exclude_dir / save event handlers.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.SettingsLive.Components

  alias MediaCentaurWeb.SettingsLive.MediaDirsLogic

  attr :config, :map,
    required: true,
    doc: "flat settings config map (`:data_dir`, `:database_path`, TTL keys)."

  attr :media_dirs, :list,
    required: true,
    doc: "list of media-dir entry maps with id / dir / name / images_dir keys."

  attr :media_dir_delete_confirm, :any, required: true, doc: "id of the dir pending delete, or nil"
  attr :scanning, :boolean, required: true

  attr :exclude_dirs, :list, required: true, doc: "list of excluded path strings."
  attr :exclude_dir_input, :string, required: true
  attr :exclude_dir_error, :any, required: true, doc: "validation error string or nil"
  attr :show_card_info, :boolean, required: true

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <form phx-submit="save_data_dir" class="glass-surface rounded-xl p-5 space-y-3">
        <.settings_card_header title="Data directory">
          <:action>
            <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
              Save
            </.button>
          </:action>
        </.settings_card_header>

        <p class="text-xs text-base-content/50 max-w-[60ch]">
          Where cached posters and backdrops are stored. Defaults next to the database.
        </p>

        <input
          type="text"
          name="data_dir"
          value={@config[:data_dir]}
          placeholder={Path.dirname(@config[:database_path] || "")}
          class="input input-bordered w-full font-mono text-sm"
          data-nav-item
          tabindex="0"
        />
      </form>

      <div class="glass-surface rounded-xl p-5 space-y-3">
        <.settings_card_header title="Media directories">
          <:action>
            <.button
              variant="action"
              size="sm"
              phx-click="media_dir:open_add"
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-plus" class="size-4" /> Add
            </.button>
          </:action>
        </.settings_card_header>

        <div :if={@media_dirs == []} class="text-base-content/60 py-4">
          No media directories configured — your library is empty. Add one to get started.
        </div>

        <ul :if={@media_dirs != []} class="space-y-2">
          <li
            :for={entry <- @media_dirs}
            class="glass-inset rounded-lg p-3 flex items-start justify-between gap-3"
          >
            <div class="min-w-0 flex-1 space-y-0.5">
              <%= if entry["name"] && entry["name"] != "" do %>
                <div class="font-medium truncate">{entry["name"]}</div>
                <div class="text-sm text-base-content/60 truncate" title={entry["dir"]}>
                  {entry["dir"]}
                </div>
              <% else %>
                <div class="font-medium truncate" title={entry["dir"]}>{entry["dir"]}</div>
              <% end %>
              <div
                :if={MediaDirsLogic.show_images_dir?(entry)}
                class="text-xs text-base-content/50 truncate"
                title={entry["images_dir"]}
              >
                Images cached at {entry["images_dir"]}
              </div>
            </div>

            <div class="flex gap-1 shrink-0">
              <.button
                variant="dismiss"
                size="sm"
                phx-click="media_dir:open_edit"
                phx-value-id={entry["id"]}
                aria-label="Edit media directory"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </.button>
              <%= if @media_dir_delete_confirm == entry["id"] do %>
                <.button
                  variant="danger"
                  size="sm"
                  phx-click="media_dir:delete"
                  phx-value-id={entry["id"]}
                  data-nav-item
                  tabindex="0"
                >
                  Confirm
                </.button>
                <.button
                  variant="dismiss"
                  size="sm"
                  phx-click="media_dir:delete_cancel"
                  data-nav-item
                  tabindex="0"
                >
                  Cancel
                </.button>
              <% else %>
                <.button
                  variant="destructive_inline"
                  size="sm"
                  phx-click="media_dir:delete_confirm"
                  phx-value-id={entry["id"]}
                  aria-label="Remove media directory"
                  data-nav-item
                  tabindex="0"
                >
                  <.icon name="hero-trash" class="size-4" />
                </.button>
              <% end %>
            </div>
          </li>
        </ul>

        <div class="mt-1 pt-4 border-t border-base-content/10 flex items-center justify-between gap-4">
          <p class="text-xs text-base-content/50 min-w-0 max-w-[60ch]">
            Scan to pick up moved or added files — moves are re-linked automatically.
          </p>
          <div class="flex items-center gap-2 shrink-0">
            <.button
              :if={@scanning}
              variant="dismiss"
              size="sm"
              phx-click="cancel_scan"
              data-nav-item
              tabindex="0"
            >
              Cancel
            </.button>
            <.button
              variant="action"
              size="sm"
              phx-click="scan"
              disabled={@scanning}
              data-nav-item
              tabindex="0"
            >
              <span :if={@scanning} class="loading loading-spinner loading-xs"></span>
              {if @scanning, do: "Scanning…", else: "Scan now"}
            </.button>
          </div>
        </div>
      </div>

      <div class="glass-surface rounded-xl p-5 space-y-3">
        <.settings_card_header title="Excluded directories" />
        <p class="text-xs text-base-content/50 max-w-[60ch]">
          Paths to ignore inside your media directories.
        </p>

        <ul :if={@exclude_dirs != []} class="space-y-2">
          <li
            :for={path <- @exclude_dirs}
            class="glass-inset rounded-lg p-3 flex items-center gap-3"
          >
            <span class="flex-1 min-w-0 text-sm truncate" title={path}>{path}</span>
            <.button
              variant="destructive_inline"
              size="sm"
              class="shrink-0"
              phx-click="exclude_dir:delete"
              phx-value-path={path}
              data-confirm={"Remove #{path} from excluded directories?"}
              aria-label="Remove excluded directory"
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-trash" class="size-4" />
            </.button>
          </li>
        </ul>

        <div :if={@exclude_dirs == []} class="text-xs text-base-content/50 py-2">
          No excluded directories.
        </div>

        <form
          phx-change="exclude_dir:validate"
          phx-submit="exclude_dir:add"
          class="space-y-1.5 pt-1"
        >
          <div class="flex gap-2">
            <input
              type="text"
              name="path"
              value={@exclude_dir_input}
              placeholder="/absolute/path/to/exclude"
              class="library-filter flex-1"
              autocomplete="off"
              data-nav-item
              tabindex="0"
            />
            <.button
              type="submit"
              variant="action"
              size="sm"
              class="shrink-0"
              disabled={exclude_dir_add_disabled?(@exclude_dir_input, @exclude_dir_error)}
              data-nav-item
              tabindex="0"
            >
              <.icon name="hero-plus" class="size-4" /> Add
            </.button>
          </div>
          <p :if={is_binary(@exclude_dir_error)} class="text-error text-xs">
            {@exclude_dir_error}
          </p>
        </form>
      </div>

      <div data-nav-grid class="glass-surface rounded-xl p-5 space-y-3">
        <.settings_card_header title="Display" />
        <.settings_field
          label="Show titles below posters"
          description="Hide for a clean wall-of-posters view."
        >
          <input
            type="checkbox"
            class="toggle toggle-sm toggle-info"
            checked={@show_card_info}
            phx-click="toggle_show_card_info"
            data-nav-item
            tabindex="0"
          />
        </.settings_field>
      </div>

      <form
        id="settings-library"
        phx-submit="save_library"
        class="glass-surface rounded-xl p-5 space-y-3"
      >
        <.settings_card_header title="Cleanup">
          <:action>
            <.button type="submit" variant="secondary" size="sm" data-nav-item tabindex="0">
              Save
            </.button>
          </:action>
        </.settings_card_header>

        <div>
          <.settings_field
            label="File absence TTL (days)"
            description="Days a missing file is kept before its entry is removed — covers unmounted drives."
          >
            <input
              type="number"
              name="file_absence_ttl_days"
              value={@config[:file_absence_ttl_days]}
              min="1"
              class="input input-bordered w-24 font-mono text-sm text-right"
              data-nav-item
              tabindex="0"
            />
          </.settings_field>

          <.settings_field
            label="Recent changes window (days)"
            description="How far back the Status page lists recent changes."
          >
            <input
              type="number"
              name="recent_changes_days"
              value={@config[:recent_changes_days]}
              min="1"
              class="input input-bordered w-24 font-mono text-sm text-right"
              data-nav-item
              tabindex="0"
            />
          </.settings_field>
        </div>
      </form>
    </div>
    """
  end

  defp exclude_dir_add_disabled?(path, error) do
    String.trim(path || "") == "" or is_binary(error)
  end
end
