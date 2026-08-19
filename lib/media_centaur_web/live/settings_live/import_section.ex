defmodule MediaCentaurWeb.SettingsLive.ImportSection do
  @moduledoc """
  The Media Import section of the Settings page — extras/skip directories,
  the match auto-approve threshold, and artwork resolution. (Named for the
  user-facing task; the machinery behind it is the Broadway pipeline.)
  `SettingsLive` delegates to `render/1` and hosts the save handler.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Settings.Config

  attr :config, :map,
    required: true,
    doc: "settings config map (reads :extras_dirs, :skip_dirs, :auto_approve_threshold)."

  def render(assigns) do
    ~H"""
    <form phx-submit="save_import" class="p-5 rounded-lg glass-surface space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h2 class="text-lg font-semibold">Media Import</h2>
          <p class="text-sm text-base-content/50 mt-0.5">
            Controls how files are classified and matched during ingestion.
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
            Extras folder names
          </label>
          <input
            type="text"
            name="extras_dirs"
            value={Enum.join(@config[:extras_dirs] || [], ", ")}
            class="input input-bordered w-full text-sm"
            placeholder="Extras, Featurettes, Special Features"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            Comma-separated folder names found within your media — files inside import as bonus content.
          </p>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Ignored folder names
          </label>
          <input
            type="text"
            name="skip_dirs"
            value={Enum.join(@config[:skip_dirs] || [], ", ")}
            class="input input-bordered w-full text-sm"
            placeholder="Sample"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            Comma-separated folder names ignored wherever they appear within your media.
            To exclude a specific path, use Library → Excluded directories.
          </p>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Auto-approve threshold
          </label>
          <input
            type="number"
            name="auto_approve_threshold"
            step="0.01"
            min="0"
            max="1"
            value={@config[:auto_approve_threshold]}
            class="input input-bordered w-full font-mono text-sm"
            data-nav-item
            tabindex="0"
          />
          <p class="text-xs text-base-content/40 mt-1">
            TMDB matches scoring above this confidence (0.0–1.0) are approved
            automatically; the rest wait in Review.
          </p>
        </div>

        <div>
          <label class="text-xs font-medium uppercase tracking-wider text-base-content/50 block mb-1.5">
            Artwork resolution
          </label>
          <select
            name="image_resolution"
            class="select select-bordered w-full text-sm"
            data-nav-item
            tabindex="0"
          >
            <option value="4k" selected={Config.image_resolution() == "4k"}>
              4K — sharper on UHD displays, larger downloads
            </option>
            <option value="1080p" selected={Config.image_resolution() == "1080p"}>
              1080p — smaller files, ideal for 1080p displays
            </option>
          </select>
          <p class="text-xs text-base-content/40 mt-1">
            Resolution for downloaded background artwork (backdrops). Applies to
            newly fetched art; existing artwork keeps its size until refreshed.
            Posters and thumbnails are always stored at a display-appropriate size.
          </p>
        </div>
      </div>
    </form>
    """
  end
end
