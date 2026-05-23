defmodule MediaCentaur.Platform.LogSource.Files do
  @moduledoc """
  macOS implementation of `MediaCentaur.Platform.LogSource`.

  Tails the log files the LaunchAgent writes via its plist
  `StandardOutPath` / `StandardErrorPath` keys. The Linux analog —
  `Platform.LogSource.Journal` — invokes `journalctl --user -u <unit> -f`;
  macOS instead spawns `tail -F <files...>` against the paths *we*
  chose when generating the plist.

  ## Default paths

  Both keys point under the user's `~/Library/Logs/` directory —
  the macOS-conventional location for application logs:

      ~/Library/Logs/Media Centaur/stdout.log
      ~/Library/Logs/Media Centaur/stderr.log

  Tests inject `paths: [...]` to redirect at a `@tmp_dir` and avoid
  touching the real home.

  ## Why `tail -F` (capital F)

  Lowercase `-f` follows the inode; if a log rotation moves the file
  out and a new one appears at the same path, `-f` keeps reading the
  old inode (now an orphaned file). `-F` re-opens the path on rename
  or truncate — the right behavior when the plist is logging into a
  rotated file.
  """

  @behaviour MediaCentaur.Platform.LogSource

  @default_log_dir "Media Centaur"
  @default_files ["stdout.log", "stderr.log"]

  @impl true
  def available?(unit, opts \\ [])

  def available?(nil, _opts), do: false

  def available?(_unit, opts) do
    paths = Keyword.get(opts, :paths) || default_paths()
    Enum.any?(paths, &File.exists?/1)
  end

  @impl true
  def open_port(unit, opts \\ [])

  def open_port(_unit, opts) do
    paths = Keyword.get(opts, :paths) || default_paths()
    find_executable = Keyword.get(opts, :find_executable, &System.find_executable/1)
    port_opener = Keyword.get(opts, :port_opener, &default_port_opener/2)

    tail = find_executable.("tail") || "/usr/bin/tail"

    port_opener.(tail,
      binary: true,
      exit_status: true,
      stderr_to_stdout: true,
      line: 4096,
      args: ["-F" | paths]
    )
  end

  defp default_paths do
    home = System.user_home!()
    base = Path.join([home, "Library", "Logs", @default_log_dir])
    Enum.map(@default_files, &Path.join(base, &1))
  end

  defp default_port_opener(path, opts) do
    Port.open({:spawn_executable, path}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      {:line, Keyword.fetch!(opts, :line)},
      args: Keyword.fetch!(opts, :args)
    ])
  end
end
