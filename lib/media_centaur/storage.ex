defmodule MediaCentaur.Storage do
  @moduledoc """
  Measures disk usage for configured directories using `df`.

  Returns a list of usage maps for watch directories and the image cache,
  suitable for rendering storage health indicators in the Operations page.
  """

  alias MediaCentaur.Config

  @type usage :: %{
          path: String.t(),
          label: String.t(),
          used_bytes: non_neg_integer(),
          total_bytes: non_neg_integer(),
          usage_percent: non_neg_integer()
        }

  @doc """
  Measures disk usage for all configured watch directories and the image cache directory.
  Returns a list of usage maps, skipping any directories that don't exist.
  """
  @spec measure_all() :: [usage()]
  def measure_all do
    watch_dirs = Config.get(:watch_dirs) || []
    images_dir = Config.get(:media_images_dir)

    watch_entries = Enum.map(watch_dirs, fn dir -> {dir, dir} end)

    image_entry =
      if images_dir, do: [{images_dir, "Image cache"}], else: []

    (watch_entries ++ image_entry)
    |> Enum.map(fn {path, label} -> measure(path, label) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Measures disk usage for a single directory path.
  Returns a usage map or `nil` if the directory doesn't exist or `df` fails.
  """
  @spec measure(String.t(), String.t()) :: usage() | nil
  def measure(path, label) do
    if File.dir?(path) do
      case System.cmd("df", ["--output=used,avail", "-B1", path], stderr_to_stdout: true) do
        {output, 0} -> parse_df_output(output, path, label)
        _ -> nil
      end
    end
  end

  @doc false
  @spec parse_df_output(String.t(), String.t(), String.t()) :: usage() | nil
  def parse_df_output(output, path, label) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> List.first()
    |> case do
      nil ->
        nil

      line ->
        case String.split(line, ~r/\s+/, trim: true) do
          [used_str, avail_str] ->
            with {used, ""} <- Integer.parse(used_str),
                 {avail, ""} <- Integer.parse(avail_str) do
              total = used + avail
              percent = if total > 0, do: round(used * 100 / total), else: 0

              %{
                path: path,
                label: label,
                used_bytes: used,
                total_bytes: total,
                usage_percent: percent
              }
            else
              _ -> nil
            end

          _ ->
            nil
        end
    end
  end
end
