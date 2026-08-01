defmodule MediaCentaurWeb.Components.Acquisition.DownloadStorage do
  @moduledoc """
  Storage-headroom logic for the download screen (logic-only — the
  rendering lives in `NeedsAttention`, UIDR-016).

  A download lands wherever the download client saves it, and free space is a
  property of the *filesystem* — so headroom is reported **per drive**, not per
  watch directory. `Storage.measure_all/0` collapses watch dirs that share a
  disk into one drive (grouped by mount point).

  ## Progressive disclosure

  Space tracks severity — a healthy library should not spend a whole card to
  say "you're fine":

    * **`:empty`** — no measured drives (still measuring / none configured).
      Nothing renders.
    * **`:calm`** — exactly one drive, healthy. No card at all; the download
      header renders `calm_summary/1` ("288 GiB free on /mnt/videos") as its
      subtitle, so a healthy library costs zero extra vertical space.
    * **`:card`** — more than one drive, *or* any drive low. Per-drive cards
      in the *Needs attention* section: free space, a usage bar coloured by
      `StatusHelpers.storage_severity/1`, and a warning icon on any drive that
      has crossed the warning/critical threshold.

  Always leads with **free space** — at grab time the question is "do I have
  room?", not "how much have I used".
  """

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
  (not by this module) so a single healthy drive costs no extra vertical
  space. Returns `nil` unless there is exactly one drive.
  """
  def calm_summary([drive]) do
    "#{StatusHelpers.format_bytes_iec(StatusHelpers.drive_free_bytes(drive))} free on #{drive.mount_point}"
  end

  def calm_summary(_drives), do: nil

  @doc """
  Per-drive card data for the *Needs attention* section — severity-coloured
  classes resolved from `StatusHelpers.storage_severity/1`, free space
  leading.
  """
  def rows(drives) do
    Enum.map(drives, fn drive ->
      severity = StatusHelpers.storage_severity(drive)

      %{
        id: drive.mount_point,
        mount_point: drive.mount_point,
        label: drive.mount_point,
        free_label: StatusHelpers.format_bytes_iec(StatusHelpers.drive_free_bytes(drive)),
        usage_percent: drive.usage_percent,
        severity: severity,
        icon: if(severity != :ok, do: "hero-exclamation-triangle-mini"),
        progress_class: StatusHelpers.storage_progress_class(severity),
        text_class: StatusHelpers.storage_text_class(severity)
      }
    end)
  end
end
