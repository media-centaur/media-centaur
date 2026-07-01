defmodule MediaCentaurWeb.Components.Acquisition.DownloadStorage do
  @moduledoc """
  Remaining-storage indicator for the download screen.

  A download lands wherever the download client saves it, and free space
  is a property of the *filesystem* — so this shows headroom **per drive**,
  not per watch directory. `Storage.measure_all/0` already collapses
  multiple watch dirs that share a disk into one drive (grouped by mount
  point), so two media dirs on the same physical disk render as a single
  row with one honest free-space number.

  Leads with **free space** ("812 GiB free") — the number that matters at
  grab time is "do I have room?", not "how much have I used". The bar and
  the free-space figure take their colour from
  `StatusHelpers.storage_severity/1`, which folds an absolute floor
  (near-full disk) and a usage percentage into one `:ok | :warning |
  :critical` classification.

  Renders nothing when there are no measured drives (still measuring, or no
  media dirs configured) — the download screen stays uncluttered rather
  than showing a permanent "measuring…" placeholder.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias MediaCentaurWeb.StatusHelpers

  @doc """
  Keeps only drives that host a media directory — the drives a download can
  actually land on.

  `Storage.measure_all/0` reports every drive backing the install (media dirs,
  image caches, the database). On the *download* screen, a drive that only
  holds the database or an image cache is noise: nothing you grab is ever
  written there, so its free space can't answer "do I have room for this?".
  A drive qualifies when any of its roles is a `"Media dir"`.
  """
  def media_dir_drives(drives) do
    Enum.filter(drives, fn drive ->
      Enum.any?(drive.roles, &(&1.label == "Media dir"))
    end)
  end

  attr :drives, :list,
    required: true,
    doc:
      "Media-dir-hosting `Storage.measure_all/0` drive maps (filter via `media_dir_drives/1`). Empty while measuring or when no media dirs are configured."

  def download_storage(%{drives: []} = assigns) do
    ~H""
  end

  def download_storage(assigns) do
    assigns = assign(assigns, :rows, Enum.map(assigns.drives, &row/1))

    ~H"""
    <div class="glass-surface rounded-xl px-4 py-3 space-y-2" data-component="download-storage">
      <div class="flex items-center gap-2">
        <.icon name="hero-circle-stack-mini" class="size-4 text-base-content/50 shrink-0" />
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Storage</h3>
      </div>

      <div class="grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
        <div :for={row <- @rows} id={"download-storage-#{row.id}"} class="space-y-1">
          <div class="flex items-baseline justify-between gap-2">
            <span class="text-sm truncate" title={row.mount_point}>{row.label}</span>
            <span class={["text-xs font-mono shrink-0", row.text_class]}>
              {row.free_label} free
            </span>
          </div>
          <progress
            class={["progress h-1.5 w-full", row.progress_class]}
            value={row.usage_percent}
            max="100"
          >
          </progress>
        </div>
      </div>
    </div>
    """
  end

  defp row(drive) do
    severity = StatusHelpers.storage_severity(drive)

    %{
      id: drive.mount_point,
      mount_point: drive.mount_point,
      label: drive.mount_point,
      free_label: StatusHelpers.format_bytes(StatusHelpers.drive_free_bytes(drive)),
      usage_percent: drive.usage_percent,
      progress_class: StatusHelpers.storage_progress_class(severity),
      text_class: StatusHelpers.storage_text_class(severity)
    }
  end
end
