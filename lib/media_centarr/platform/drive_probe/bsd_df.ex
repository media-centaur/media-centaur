defmodule MediaCentarr.Platform.DriveProbe.BsdDf do
  @moduledoc """
  macOS / BSD implementation of `MediaCentarr.Platform.DriveProbe`.

  Shells out to `df -k -P PATH`:

  * `-k` — report in 1024-byte blocks (multiply by 1024 for bytes).
  * `-P` — POSIX output format (one row per filesystem; no wrapping
    on long device names; columns are stable).

  GNU `df --output=...` doesn't exist on BSD `df`; that's what
  `Platform.DriveProbe.GnuDf` uses on Linux. Same `drive_info()`
  return type; the difference is just in how we shell out + parse.

  ## POSIX `df -P` row shape

      Filesystem    1024-blocks  Used    Available  Capacity  Mounted on
      /dev/disk3s1  488245288    12345   100000000  11%       /

  Columns are whitespace-separated; the mount-point column may
  contain spaces, so everything from column 6 onward is rejoined.
  """

  @behaviour MediaCentarr.Platform.DriveProbe

  @impl true
  def available_bytes(path, opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/3)

    # `env: []` clears the inherited environment so we don't leak
    # credentials into a subprocess that doesn't need them. `df`
    # only needs locale-related env which we don't depend on.
    case cmd_fn.("df", ["-k", "-P", path], stderr_to_stdout: true, env: []) do
      {output, 0} ->
        case first_data_row(output) do
          nil -> :error
          line -> with {:ok, info} <- parse_line(line), do: {:ok, info.total_bytes - info.used_bytes}
        end

      _ ->
        :error
    end
  end

  @impl true
  def measure(path, opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/3)

    case cmd_fn.("df", ["-k", "-P", path], stderr_to_stdout: true, env: []) do
      {output, 0} ->
        case first_data_row(output) do
          nil -> :error
          line -> parse_line(line)
        end

      _ ->
        :error
    end
  end

  @doc """
  Parses a single data line from `df -k -P` output into a drive
  info map. Returns `{:ok, info}` or `:error`.
  """
  @spec parse_line(String.t()) :: {:ok, MediaCentarr.Platform.DriveProbe.drive_info()} | :error
  def parse_line(line) do
    case String.split(line, ~r/\s+/, trim: true) do
      [source, blocks_str, used_str, avail_str, _capacity | mount_parts]
      when mount_parts != [] ->
        mount_point = Enum.join(mount_parts, " ")

        with {blocks_used, ""} <- Integer.parse(used_str),
             {blocks_avail, ""} <- Integer.parse(avail_str),
             {_blocks_total, ""} <- Integer.parse(blocks_str) do
          used_bytes = blocks_used * 1024
          total_blocks = blocks_used + blocks_avail
          total_bytes = total_blocks * 1024

          percent =
            if total_blocks > 0,
              do: round(blocks_used * 100 / total_blocks),
              else: 0

          {:ok,
           %{
             device: Path.basename(source),
             mount_point: mount_point,
             used_bytes: used_bytes,
             total_bytes: total_bytes,
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

  # `df -k -P` always emits one header row then one data row per
  # filesystem (no line-wrapping). Pick the first non-header row.
  defp first_data_row(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> List.first()
  end
end
