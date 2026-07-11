defmodule MediaCentaurWeb.Components.Acquisition.DownloadStorage do
  @moduledoc """
  Remaining-storage indicator for the download screen.

  A download lands wherever the download client saves it, and free space is a
  property of the *filesystem* — so this shows headroom **per drive**, not per
  watch directory. `Storage.measure_all/0` collapses watch dirs that share a
  disk into one drive (grouped by mount point).

  ## Progressive disclosure

  Space tracks severity — a healthy library should not spend a whole card to
  say "you're fine":

    * **`:empty`** — no measured drives (still measuring / none configured).
      Renders nothing.
    * **`:calm`** — exactly one drive, healthy. No card at all; the download
      header renders `calm_summary/1` ("288 GiB free on /mnt/videos") as its
      subtitle, so a healthy library costs zero extra vertical space.
    * **`:card`** — more than one drive, *or* any drive low. The full card:
      per-drive rows with free space, a usage bar coloured by
      `StatusHelpers.storage_severity/1`, and a warning icon on any drive that
      has crossed the warning/critical threshold.

  Always leads with **free space** — at grab time the question is "do I have
  room?", not "how much have I used".
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

  @doc """
  Chooses the disclosure level for a set of media-dir drives:
  `:empty | :calm | :card` (see the moduledoc). The card is reserved for the
  cases that genuinely warrant the space — more than one drive, or a drive
  that has crossed the warning/critical threshold.
  """
  def display_mode([]), do: :empty

  def display_mode([drive]) do
    case StatusHelpers.storage_severity(drive) do
      :ok -> :calm
      _low -> :card
    end
  end

  def display_mode(_drives), do: :card

  @doc """
  One-line free-space summary for the `:calm` case, e.g.
  `"288 GiB free on /mnt/videos"`. Rendered as the download header's subtitle
  (not by this component) so a single healthy drive costs no extra vertical
  space. Returns `nil` unless there is exactly one drive.
  """
  def calm_summary([drive]) do
    "#{StatusHelpers.format_bytes(StatusHelpers.drive_free_bytes(drive))} free on #{drive.mount_point}"
  end

  def calm_summary(_drives), do: nil

  attr :drives, :list,
    required: true,
    doc:
      "Media-dir-hosting `Storage.measure_all/0` drive maps (filter via `media_dir_drives/1`). Renders the escalated card only (`:card` mode); the `:calm` single-healthy-drive case is shown in the header subtitle via `calm_summary/1`."

  def download_storage(assigns) do
    assigns =
      assigns
      |> assign(:mode, display_mode(assigns.drives))
      |> assign(:rows, Enum.map(assigns.drives, &row/1))

    ~H"""
    <%!-- An open section like its neighbors (Coming up / Recently landed),
          not one boxed panel: "Storage" is the section heading and each
          drive gets its own half-wide glass card (owner call, 2026-07-11) —
          bookkeeping voice, never a page-wide alarm band. --%>
    <section :if={@mode == :card} class="space-y-3" data-component="download-storage" data-mode="card">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Storage
      </h3>

      <div class="grid gap-3 sm:grid-cols-2">
        <div
          :for={row <- @rows}
          id={"download-storage-#{row.id}"}
          class="glass-surface rounded-xl px-4 py-3 space-y-1.5"
        >
          <div class="flex items-baseline justify-between gap-2">
            <span class="flex items-center gap-1.5 truncate text-sm" title={row.mount_point}>
              <.icon :if={row.icon} name={row.icon} class={"size-4 shrink-0 #{row.text_class}"} />
              {row.label}
            </span>
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
    </section>
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
      severity: severity,
      icon: if(severity != :ok, do: "hero-exclamation-triangle-mini"),
      progress_class: StatusHelpers.storage_progress_class(severity),
      text_class: StatusHelpers.storage_text_class(severity)
    }
  end
end
