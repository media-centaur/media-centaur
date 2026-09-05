defmodule MediaCentaurWeb.SettingsLive.Danger do
  @moduledoc """
  The Danger Zone section of the Settings page — irreversible destructive
  actions only, i.e. the clear-database control. Recoverable repair actions
  live in `MediaCentaurWeb.SettingsLive.MaintenanceSection`. `SettingsLive`
  delegates to `render/1` and hosts the action handlers.
  """

  use MediaCentaurWeb, :html

  attr :clearing_database, :boolean, required: true

  def render(assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface border border-error/20 space-y-4">
      <div class="flex items-start gap-3">
        <.icon name="hero-exclamation-triangle" class="size-6 text-error shrink-0 mt-0.5" />
        <div class="min-w-0">
          <h2 class="text-lg font-semibold text-error">Danger Zone</h2>
          <p class="text-sm text-base-content/60 mt-0.5">
            Destructive actions that cannot be undone. Read the prompt carefully before confirming.
          </p>
        </div>
      </div>

      <div class="flex items-start justify-between gap-4 pt-1">
        <div class="min-w-0">
          <p class="text-sm font-medium">Clear database</p>
          <p class="text-xs text-base-content/55 mt-0.5">
            Permanently deletes all entities, files, images, and progress.
          </p>
        </div>
        <%!-- Irreversible and unbounded, so it earns the heaviest
              confirmation we have: a persistent modal, rendered at the
              SettingsLive root. MC0027 has the full rule. --%>
        <.button
          variant="danger"
          size="sm"
          class="shrink-0"
          phx-click="clear_database_prompt"
          disabled={@clearing_database}
          data-nav-item
          tabindex="0"
        >
          {if @clearing_database, do: "Clearing…", else: "Clear"}
        </.button>
      </div>
    </div>
    """
  end
end
