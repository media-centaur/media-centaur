defmodule MediaCentaurWeb.SettingsLive.MaintenanceSection do
  @moduledoc """
  The Maintenance section of the Settings page — recoverable repair actions
  for the library's metadata and cached artwork (image repair, credits and
  subtitle refresh, extra-name rederive, backdrop re-fetch, full image-cache
  refresh). Split out of the Danger Zone so the irreversible Clear database
  keeps a section to itself. `SettingsLive` delegates to `render/1` and
  hosts the action handlers.
  """

  use MediaCentaurWeb, :html

  attr :blank_extra_names_count, :integer, required: true

  attr :missing_images_summary, :any,
    required: true,
    doc: "summary string/map of entities missing artwork."

  attr :confirming_image_refresh, :boolean,
    required: true,
    doc: "true once the Refresh button is armed and awaiting its second click."

  attr :rederiving_extra_names, :boolean, required: true
  attr :refetching_backdrops, :boolean, required: true
  attr :refreshing_credits, :boolean, required: true
  attr :refreshing_images, :boolean, required: true
  attr :refreshing_movie_subtitles, :boolean, required: true
  attr :refreshing_series_credits, :boolean, required: true
  attr :repairing_images, :boolean, required: true

  def render(assigns) do
    ~H"""
    <div data-nav-grid class="p-5 rounded-lg glass-surface space-y-4">
      <div class="flex items-start gap-3">
        <.icon name="hero-wrench-screwdriver" class="size-6 text-base-content/70 shrink-0 mt-0.5" />
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Library maintenance</h2>
          <p class="text-sm text-base-content/60 mt-0.5">
            Detect and heal gaps in the library's metadata and cached artwork.
            Everything here is recoverable.
          </p>
        </div>
      </div>

      <div class="divide-y divide-base-content/10">
        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">
              Repair missing images
              <.badge
                :if={@missing_images_summary.missing > 0}
                variant="warning"
                class="ml-2"
              >
                {@missing_images_summary.missing} missing
              </.badge>
            </p>
            <p class="text-xs text-base-content/50 mt-0.5">
              <%= if @missing_images_summary.missing > 0 do %>
                Finds {@missing_images_summary.missing} image file{if @missing_images_summary.missing ==
                                                                        1,
                                                                      do: "",
                                                                      else: "s"} referenced in the database but absent on disk, and re-queues each one for download from TMDB. Reuses stored source URLs where available; re-queries TMDB when the queue entry is missing.
              <% else %>
                All image files are present on disk. Nothing to repair.
              <% end %>
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="repair_missing_images"
            disabled={@repairing_images or @missing_images_summary.missing == 0}
            data-nav-item
            tabindex="0"
          >
            {if @repairing_images, do: "Repairing…", else: "Repair"}
          </.button>
        </div>

        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">
              Re-derive bonus-feature names
              <.badge :if={@blank_extra_names_count > 0} variant="warning" class="ml-2">
                {@blank_extra_names_count} blank
              </.badge>
            </p>
            <p class="text-xs text-base-content/50 mt-0.5">
              Re-reads each bonus feature's name from its file path, healing blank or
              out-of-date names left by an earlier parsing bug. Network-free and safe to
              re-run — also picks up naming improvements after an update.
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="rederive_extra_names"
            disabled={@rederiving_extra_names}
            data-nav-item
            tabindex="0"
          >
            {if @rederiving_extra_names, do: "Re-deriving…", else: "Re-derive"}
          </.button>
        </div>

        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">Re-fetch backdrops</p>
            <p class="text-xs text-base-content/50 mt-0.5">
              Re-downloads every backdrop at the current artwork resolution
              (Pipeline → Artwork resolution) and clears the old cached copies to
              reclaim space. Use after changing the resolution to bring existing
              artwork in line. Posters and thumbnails are unaffected.
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="refetch_backdrops"
            disabled={@refetching_backdrops}
            data-nav-item
            tabindex="0"
          >
            {if @refetching_backdrops, do: "Re-fetching…", else: "Re-fetch"}
          </.button>
        </div>

        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">Refresh movie credits</p>
            <p class="text-xs text-base-content/50 mt-0.5">
              Backfills cast, crew (director, writers, composer), and IMDb ids for movies imported before those fields existed. Skips movies that already have credits — safe to re-run.
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="refresh_movie_credits"
            disabled={@refreshing_credits}
            data-nav-item
            tabindex="0"
          >
            {if @refreshing_credits, do: "Refreshing…", else: "Refresh"}
          </.button>
        </div>

        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">Refresh series credits</p>
            <p class="text-xs text-base-content/50 mt-0.5">
              Backfills creators, aggregate cast, and IMDb ids for TV series imported before those fields existed. Skips series that already have credits — safe to re-run.
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="refresh_series_credits"
            disabled={@refreshing_series_credits}
            data-nav-item
            tabindex="0"
          >
            {if @refreshing_series_credits, do: "Refreshing…", else: "Refresh"}
          </.button>
        </div>

        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">Refresh movie subtitles</p>
            <p class="text-xs text-base-content/50 mt-0.5">
              Detects subtitle tracks (embedded streams via ffprobe + sidecar files) for movies imported before subtitle detection shipped. Skips files that already have tracks — safe to re-run.
            </p>
          </div>
          <.button
            variant="neutral"
            size="sm"
            class="shrink-0"
            phx-click="refresh_movie_subtitles"
            disabled={@refreshing_movie_subtitles}
            data-nav-item
            tabindex="0"
          >
            {if @refreshing_movie_subtitles, do: "Refreshing…", else: "Refresh"}
          </.button>
        </div>

        <div class="flex items-start justify-between gap-4 py-3">
          <div class="min-w-0">
            <p class="text-sm font-medium">Refresh image cache</p>
            <p class="text-xs text-base-content/50 mt-0.5">
              Deletes all cached artwork and re-downloads from TMDB. May take a while.
            </p>
          </div>
          <%!-- Recoverable — the artwork comes back, it just takes a while
                — so it arms in place rather than raising a modal. Same
                Confirm/Cancel swap the media-directory rows use, so the
                page has one in-place idiom. MC0027 has the full rule. --%>
          <div class="flex items-center gap-2 shrink-0">
            <%= if @confirming_image_refresh and not @refreshing_images do %>
              <.button
                variant="risky"
                size="sm"
                phx-click="refresh_image_cache"
                data-nav-item
                tabindex="0"
              >
                Confirm
              </.button>
              <.button
                variant="dismiss"
                size="sm"
                phx-click="refresh_image_cache_cancel"
                data-nav-item
                tabindex="0"
              >
                Cancel
              </.button>
            <% else %>
              <.button
                variant="risky"
                size="sm"
                phx-click="refresh_image_cache_confirm"
                disabled={@refreshing_images}
                data-nav-item
                tabindex="0"
              >
                {if @refreshing_images, do: "Refreshing…", else: "Refresh"}
              </.button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
