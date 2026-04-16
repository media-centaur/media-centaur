defmodule MediaCentarr.Storage do
  @moduledoc """
  Measures disk usage for configured directories using `df`.

  Returns a list of drive maps grouped by mount point, each containing
  capacity info and the roles (watch dirs, image caches, database) that
  reside on that drive. Used by the Operations page storage section.
  """

  alias MediaCentarr.Config

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
  """
  @spec available_bytes(String.t()) :: {:ok, non_neg_integer()} | :error
  def available_bytes(path) do
    case System.cmd("df", ["--output=avail", "-B1", path], stderr_to_stdout: true) do
      {output, 0} -> parse_avail(output)
      _ -> :error
    end
  end

  @doc """
  Parses a single data line from `df --output=source,used,avail,target -B1` output
  into a drive info map. Returns `{:ok, info}` or `:error`.
  """
  @spec parse_df_line(String.t()) :: {:ok, map()} | :error
  def parse_df_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [source, used_str, avail_str | rest] when rest != [] ->
        mount_point = Enum.join(rest, " ")

        with {used, ""} <- Integer.parse(used_str),
             {avail, ""} <- Integer.parse(avail_str) do
          total = used + avail
          percent = if total > 0, do: round(used * 100 / total), else: 0

          {:ok,
           %{
             device: Path.basename(source),
             mount_point: mount_point,
             used_bytes: used,
             total_bytes: total,
             usage_percent: percent
           }}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

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
      case System.cmd("df", ["--output=source,used,avail,target", "-B1", path],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          output
          |> String.split("\n", trim: true)
          |> Enum.drop(1)
          |> List.first()
          |> case do
            nil -> nil
            line -> with {:ok, info} <- parse_df_line(line), do: {path, label, info}
          end

        _ ->
          nil
      end
    end
  end

  defp parse_avail(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> List.first()
    |> case do
      nil ->
        :error

      line ->
        case line |> String.trim() |> Integer.parse() do
          {bytes, ""} -> {:ok, bytes}
          _ -> :error
        end
    end
  end
end
