defmodule MediaCentaurWeb.SettingsLive.Library do
  @moduledoc """
  The Library section of the Settings page (UIDR-041): the data directory
  as a text row, the media directories (add/edit/remove, scan), the
  ignore rules as two validated list settings, and the cleanup windows as
  steppers. `SettingsLive` delegates to `render/1` and hosts the
  media_dir / ignore_rule / save / set event handlers. `days_ladder/0` is
  the cleanup steppers' rungs, shared with the handler that validates
  them.

  The two ignore-rule lists share one card because they are one idea
  with two matching modes — a path and everything under it, or a folder
  name wherever it appears. They were two cards in separate sections
  that each pointed at the other in prose.
  """

  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.Settings

  alias MediaCentaur.Settings.Ladder
  alias MediaCentaurWeb.SettingsLive.MediaDirsLogic

  @absence_default 30
  @recent_default 3

  attr :config, :map,
    required: true,
    doc: "flat settings config map (`:data_dir`, `:database_path`, TTL keys)."

  attr :media_dirs, :list,
    required: true,
    doc: "list of media-dir entry maps with id / dir / name / images_dir keys."

  attr :media_dir_delete_confirm, :any, required: true, doc: "id of the dir pending delete, or nil"
  attr :scanning, :boolean, required: true

  attr :ignore_rules, :map,
    required: true,
    doc: "`%{path: [absolute paths], name: [folder names]}` — the two ignore-rule kinds."

  attr :ignore_rule_input, :map, required: true, doc: "the add input's text, keyed by kind."

  attr :ignore_rule_error, :map,
    required: true,
    doc: "inline validation error per kind — a string or nil."

  def render(assigns) do
    assigns =
      assign(assigns,
        absence_days: assigns.config[:file_absence_ttl_days] || @absence_default,
        recent_days: assigns.config[:recent_changes_days] || @recent_default,
        absence_default: @absence_default,
        recent_default: @recent_default
      )

    ~H"""
    <div class="space-y-4">
      <.settings_card title="Data directory">
        <.settings_text_row
          id="data-dir"
          label="Location"
          description="Where cached posters and backdrops are stored. Defaults next to the database."
          name="data_dir"
          value={@config[:data_dir]}
          placeholder={Path.dirname(@config[:database_path] || "")}
          event="save_data_dir"
          mono
        />
      </.settings_card>

      <.settings_card title="Media directories">
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
                <div class="text-sm text-base-content/60 truncate-left" title={entry["dir"]}>
                  <bdo dir="ltr">{entry["dir"]}</bdo>
                </div>
              <% else %>
                <div class="font-medium truncate-left" title={entry["dir"]}>
                  <bdo dir="ltr">{entry["dir"]}</bdo>
                </div>
              <% end %>
              <div
                :if={MediaDirsLogic.show_images_dir?(entry)}
                class="text-xs text-base-content/55 flex gap-1 min-w-0"
                title={entry["images_dir"]}
              >
                <span class="shrink-0">Images cached at</span>
                <span class="truncate-left"><bdo dir="ltr">{entry["images_dir"]}</bdo></span>
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

        <%!-- With no directories configured there is nothing to scan, so the
              row would offer a control that cannot do anything. --%>
        <div
          :if={@media_dirs != []}
          class="mt-1 pt-4 border-t border-base-content/10 flex items-center justify-between gap-4"
        >
          <p class="text-xs text-base-content/55 min-w-0 max-w-[60ch]">
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
      </.settings_card>

      <.settings_card
        title="Ignore rules"
        description="Parts of your media directories that are never scanned. Nothing inside them is imported; to ignore somewhere you have already imported from, remove those titles from your library first."
      >
        <div class="space-y-5">
          <.settings_list
            id="ignore-rules-path"
            label="By path"
            items={@ignore_rules.path}
            remove_event="ignore_rule:delete"
            add_event="ignore_rule:add"
            change_event="ignore_rule:validate"
            event_value={%{"kind" => "path"}}
            value={@ignore_rule_input.path}
            add_disabled={add_disabled?(@ignore_rule_input.path, @ignore_rule_error.path)}
            error={@ignore_rule_error.path}
            placeholder="/absolute/path/to/ignore"
            mono
            truncate_left
          />
          <.settings_list
            id="ignore-rules-name"
            label="By folder name"
            items={@ignore_rules.name}
            remove_event="ignore_rule:delete"
            add_event="ignore_rule:add"
            change_event="ignore_rule:validate"
            event_value={%{"kind" => "name"}}
            value={@ignore_rule_input.name}
            add_disabled={add_disabled?(@ignore_rule_input.name, @ignore_rule_error.name)}
            error={@ignore_rule_error.name}
            placeholder="Sample"
          />
        </div>
      </.settings_card>

      <.settings_card title="Cleanup">
        <div class="space-y-0.5">
          <.settings_stepper
            id="absence-ttl"
            label="Keep a missing file's entry for"
            description="Covers unmounted drives: the entry is removed only after this many days absent."
            value_label={days(@absence_days)}
            down_value={Ladder.down(days_ladder(), @absence_days)}
            up_value={Ladder.up(days_ladder(), @absence_days)}
            reset_value={@absence_default}
            at_min={@absence_days <= 1}
            at_max={@absence_days >= List.last(days_ladder())}
            at_default={@absence_days == @absence_default}
            event="set_absence_ttl_days"
          />
          <.settings_stepper
            id="recent-changes"
            label="Recent changes window"
            description="How far back the Status page lists recent changes."
            value_label={days(@recent_days)}
            down_value={Ladder.down(days_ladder(), @recent_days)}
            up_value={Ladder.up(days_ladder(), @recent_days)}
            reset_value={@recent_default}
            at_min={@recent_days <= 1}
            at_max={@recent_days >= List.last(days_ladder())}
            at_default={@recent_days == @recent_default}
            event="set_recent_changes_days"
          />
        </div>
      </.settings_card>
    </div>
    """
  end

  @doc "The cleanup steppers' rungs: every day up to two weeks, every five days to a month, then 45, 60 and 90."
  @spec days_ladder() :: [pos_integer()]
  def days_ladder, do: Ladder.range(1, 14, 1) ++ [15, 20, 25, 30, 45, 60, 90]

  defp days(1), do: "1 day"
  defp days(n), do: "#{n} days"

  defp add_disabled?(input, error) do
    String.trim(input || "") == "" or is_binary(error)
  end
end
