defmodule MediaCentarr.SelfUpdate.Stager do
  @moduledoc """
  Validates and extracts a Media Centarr release tarball into a staging
  directory — the contract-validation step between "bytes arrived" and
  "shell installer is allowed to run."

  ## Security posture

  Every entry in the tarball is validated **before** extraction:

    * Absolute paths are rejected (`/etc/passwd` → `:absolute_path`).
    * Any `..` segment is rejected (`../escape` or `a/../b` → `:path_traversal`).
    * Symlinks and hard links are rejected (mix releases don't need them —
      accepting them would open directory escape via link-swap races).
    * Non-regular, non-directory entries (device files, FIFOs, sockets) are
      rejected.
    * Cumulative declared size is capped — any tarball claiming to expand
      beyond `:max_bytes` aborts extraction.

  After a successful extraction, the required mix-release members are
  checked for presence (not content) — if the bundled installer or
  systemd unit is missing, handoff is aborted rather than handing off to
  an installer binary that won't know how to migrate.

  The staging directory is created fresh with `0o700` so another local
  process can't read in-flight extracted artifacts.
  """

  @default_max_bytes 1_000_000_000
  @default_required [
    "bin/media-centarr-install",
    "bin/media_centarr",
    "share/systemd/media-centarr.service",
    "share/defaults/media-centarr.toml"
  ]

  @type entry ::
          {:erl_tar.tar_entry(), :regular | :directory | :symlink | atom(), non_neg_integer(), integer(),
           integer(), integer(), integer()}

  @type extract_error ::
          :absolute_path
          | :path_traversal
          | :symlink
          | :non_regular_file
          | :oversized
          | {:missing_required, [String.t()]}
          | {:tar_error, term()}

  @doc """
  Extracts a gzipped tar file into `target_dir`.

  Options:

    * `:max_bytes` — total declared size cap (default 1 GB).
    * `:required` — list of relative paths that must be present in the
      extracted tree. Default covers the mix release's bundled installer
      and systemd unit.
  """
  @spec extract(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, extract_error()}
  def extract(tarball_path, target_dir, opts \\ []) do
    max_bytes = Keyword.get(opts, :max_bytes, @default_max_bytes)
    required = Keyword.get(opts, :required, @default_required)

    with {:ok, entries} <- read_table(tarball_path),
         :ok <- validate_entries(entries, max_bytes),
         :ok <- prepare_staging(target_dir),
         :ok <- do_extract(tarball_path, target_dir),
         :ok <- check_required(target_dir, required) do
      {:ok, target_dir}
    end
  end

  @doc """
  Pure validator — used by `extract/3` and exposed for unit testing against
  synthetic entry tuples so the test suite doesn't need to hand-craft
  malformed tarballs for every corner case.
  """
  @spec validate_entries(list(), pos_integer()) :: :ok | {:error, extract_error()}
  def validate_entries(entries, max_bytes) do
    entries
    |> Enum.reduce_while({:ok, 0}, fn entry, {:ok, acc} ->
      case validate_entry(entry, acc, max_bytes) do
        {:ok, new_acc} -> {:cont, {:ok, new_acc}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp validate_entry({name, type, size, _mtime, _mode, _uid, _gid}, acc, max_bytes) do
    with :ok <- validate_type(type),
         :ok <- validate_path(name) do
      new_acc = acc + safe_size(size, type)

      if new_acc > max_bytes do
        {:error, :oversized}
      else
        {:ok, new_acc}
      end
    end
  end

  defp validate_type(:regular), do: :ok
  defp validate_type(:directory), do: :ok
  defp validate_type(:symlink), do: {:error, :symlink}
  defp validate_type(_other), do: {:error, :non_regular_file}

  defp validate_path(name) do
    path = to_string(name)

    cond do
      String.starts_with?(path, "/") ->
        {:error, :absolute_path}

      path_has_traversal?(path) ->
        {:error, :path_traversal}

      true ->
        :ok
    end
  end

  defp path_has_traversal?(path) do
    path
    |> Path.split()
    |> Enum.any?(&(&1 == ".."))
  end

  defp safe_size(size, :regular) when is_integer(size) and size >= 0, do: size
  defp safe_size(_size, _type), do: 0

  defp read_table(path) do
    case :erl_tar.table(String.to_charlist(path), [:compressed, :verbose]) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:tar_error, reason}}
    end
  end

  defp prepare_staging(dir) do
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)
    :ok
  end

  defp do_extract(tarball_path, target_dir) do
    case :erl_tar.extract(String.to_charlist(tarball_path), [
           :compressed,
           {:cwd, String.to_charlist(target_dir)}
         ]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:tar_error, reason}}
    end
  end

  defp check_required(target_dir, required) do
    missing =
      Enum.reject(required, fn path ->
        target_dir |> Path.join(path) |> File.exists?()
      end)

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_required, missing}}
    end
  end
end
