defmodule MediaCentarr.Platform.DriveProbe.GnuDf do
  @moduledoc """
  Linux implementation of `MediaCentarr.Platform.DriveProbe`.

  Shells out to GNU `df` with explicit `--output=...` columns and
  `-B1` (byte units). The flags are GNU-only — BSD `df` (macOS) uses
  a different parser (see `Platform.DriveProbe.BsdDf`, future phase).

  Lifted verbatim from the original `MediaCentarr.Storage.{available_bytes/1,
  parse_df_line/1, measure_with_drive_info/2}` — no logic edits, just
  relocated under the `Platform.*` namespace.
  """

  @behaviour MediaCentarr.Platform.DriveProbe

  @impl true
  def available_bytes(path, opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/3)

    # `env: []` clears the inherited environment so we don't leak credentials
    # (TMDB key, qBittorrent password, etc.) into a subprocess that doesn't
    # need them. `df` only needs LANG-style locale settings to format output,
    # which we don't depend on.
    case cmd_fn.("df", ["--output=avail", "-B1", path], stderr_to_stdout: true, env: []) do
      {output, 0} -> parse_avail(output)
      _ -> :error
    end
  end

  @impl true
  def measure(path, opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/3)

    case cmd_fn.("df", ["--output=source,used,avail,target", "-B1", path],
           stderr_to_stdout: true,
           env: []
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.drop(1)
        |> List.first()
        |> case do
          nil -> :error
          line -> parse_line(line)
        end

      _ ->
        :error
    end
  end

  @doc """
  Parses a single data line from `df --output=source,used,avail,target -B1`
  output into a drive info map. Returns `{:ok, info}` or `:error`.
  """
  @spec parse_line(String.t()) :: {:ok, MediaCentarr.Platform.DriveProbe.drive_info()} | :error
  def parse_line(line) do
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

  # --- Private ---

  defp default_cmd(binary, args, opts), do: System.cmd(binary, args, opts)

  defp parse_avail(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> List.first()
    |> case do
      nil ->
        :error

      line ->
        line
        |> String.trim()
        |> Integer.parse()
        |> case do
          {bytes, ""} -> {:ok, bytes}
          _ -> :error
        end
    end
  end
end
