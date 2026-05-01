defmodule MediaCentarr.Watcher.MountStatus do
  @moduledoc """
  Pure decision logic for the per-directory watcher's health check.

  The "device id" is `{major_device, minor_device}` from `File.stat/1`,
  or `nil` when the path is currently inaccessible. A device-id change
  for the same path is the kernel-level signal that a filesystem was
  mounted (or unmounted) at that path — including the
  startup-before-mount case where the watcher attached its inotify
  watch to an empty pre-mount directory and the real drive was mounted
  on top of it later. inotify watches inodes, not paths, so the watcher
  has no way to notice that on its own.

  ## Returned actions

  - `:keep_watching` — no change required.
  - `:keep_unavailable` — still inaccessible; keep polling.
  - `:reinit_remount` — device id changed under us; tear the inotify
    watcher down and re-init against the new mount.
  - `:reinit_restored` — directory is accessible again after being
    unavailable; re-init.
  - `:transition_unavailable` — directory just disappeared; broadcast
    and stop forwarding events.
  """

  @type device_id :: {non_neg_integer(), non_neg_integer()} | nil
  @type watcher_state :: :initializing | :watching | :unavailable
  @type action ::
          :keep_watching
          | :keep_unavailable
          | :reinit_remount
          | :reinit_restored
          | :transition_unavailable

  @doc """
  Returns the action the watcher should take given its current state,
  the device id captured when it last started watching, and the device
  id observed right now.
  """
  @spec action(watcher_state(), device_id(), device_id()) :: action()
  def action(:initializing, _prev, _current), do: :keep_watching

  def action(:watching, _prev, nil), do: :transition_unavailable
  def action(:watching, nil, _current), do: :keep_watching
  def action(:watching, prev, current) when prev == current, do: :keep_watching
  def action(:watching, _prev, _current), do: :reinit_remount

  def action(:unavailable, _prev, nil), do: :keep_unavailable
  def action(:unavailable, _prev, _current), do: :reinit_restored
end
