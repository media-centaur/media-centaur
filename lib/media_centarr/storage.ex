defmodule MediaCentarr.Storage do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Aggregates disk-capacity info for configured directories.

  Owns the *orchestration* — which paths matter (watch dirs, image
  caches, database), how to group results by mount point — but
  delegates the OS-specific "ask the kernel how much space is left"
  probe to `MediaCentarr.Platform.DriveProbe`. That keeps GNU/BSD
  `df` flag differences quarantined to the Platform namespace.

  Used by the Operations page storage section.
  """

  alias MediaCentarr.Config
  alias MediaCentarr.Platform.DriveProbe

  @type role :: %{label: String.t(), path: String.t()}

  @type drive :: %{
          mount_point: String.t(),
          device: String.t(),
          used_bytes: non_neg_integer(),
          total_bytes: non_neg_integer(),
          usage_percent: non_neg_integer(),
          roles: [role()]
        }

  @doc """
  Measures disk usage for all configured watch directories, their image caches,
  and the database. Returns a list of drive maps grouped by mount point.
  """
  @spec measure_all() :: [drive()]
  def measure_all do
    watch_dirs = Config.get(:watch_dirs) || []
    database_path = Config.get(:database_path)

    role_paths =
      Enum.flat_map(watch_dirs, fn dir ->
        [{dir, "Watch dir"}, {Config.images_dir_for(dir), "Image cache"}]
      end)

    role_paths =
      if database_path, do: role_paths ++ [{database_path, "Database"}], else: role_paths

    role_paths
    |> Enum.map(fn {path, label} -> measure_with_drive_info(path, label) end)
    |> Enum.reject(&is_nil/1)
    |> group_by_drive()
  end

  @doc """
  Returns the number of available bytes on the filesystem containing `path`.

  Thin delegate to `Platform.DriveProbe.available_bytes/1` — kept on
  `Storage` so existing consumers (`Pipeline.Import`) don't need to
  learn the new namespace.
  """
  @spec available_bytes(String.t()) :: {:ok, non_neg_integer()} | :error
  def available_bytes(path), do: DriveProbe.available_bytes(path)

  @doc """
  Groups measured entries by mount point into drive maps.
  Each drive gets one set of capacity numbers and a list of roles.
  """
  @spec group_by_drive([{String.t(), String.t(), map()}]) :: [drive()]
  def group_by_drive(entries) do
    entries
    |> Enum.group_by(fn {_path, _label, info} -> info.mount_point end)
    |> Enum.map(fn {_mount_point, group} ->
      {_path, _label, info} = hd(group)

      %{
        mount_point: info.mount_point,
        device: info.device,
        used_bytes: info.used_bytes,
        total_bytes: info.total_bytes,
        usage_percent: info.usage_percent,
        roles: Enum.map(group, fn {path, label, _info} -> %{label: label, path: path} end)
      }
    end)
  end

  # --- Private ---

  defp measure_with_drive_info(path, label) do
    path = if label == "Database", do: Path.dirname(path), else: path

    if File.dir?(path) do
      case DriveProbe.measure(path) do
        {:ok, info} -> {path, label, info}
        :error -> nil
      end
    end
  end
end
