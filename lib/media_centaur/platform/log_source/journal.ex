defmodule MediaCentaur.Platform.LogSource.Journal do
  @moduledoc """
  Linux implementation of `MediaCentaur.Platform.LogSource`.

  Spawns `journalctl --user -u <unit> -n 200 -f --output=short-iso`
  via `Port.open/2`. The port emits one `{port, {:data, {:eol, line}}}`
  message per log line, consumed by
  `MediaCentaur.Console.JournalSource`'s GenServer loop.

  Lifted verbatim from the original
  `Console.JournalSource.default_port_opener/1` — no logic edits.
  """

  @behaviour MediaCentaur.Platform.LogSource

  @prime_line_count 200

  @impl true
  def available?(unit, opts \\ [])

  def available?(nil, _opts), do: false

  def available?(_unit, opts) do
    find_executable = Keyword.get(opts, :find_executable, &System.find_executable/1)
    find_executable.("journalctl") != nil
  end

  @impl true
  def open_port(unit, opts \\ []) do
    find_executable = Keyword.get(opts, :find_executable, &System.find_executable/1)
    port_opener = Keyword.get(opts, :port_opener, &default_port_opener/2)

    path = find_executable.("journalctl") || "/usr/bin/journalctl"

    port_opener.(path,
      binary: true,
      exit_status: true,
      stderr_to_stdout: true,
      line: 4096,
      args: [
        "--user",
        "-u",
        unit,
        "-n",
        Integer.to_string(@prime_line_count),
        "-f",
        "--output=short-iso"
      ]
    )
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
