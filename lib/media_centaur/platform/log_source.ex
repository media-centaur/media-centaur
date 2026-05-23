defmodule MediaCentaur.Platform.LogSource do
  @moduledoc """
  Live log-source seam — the OS-specific subprocess that emits
  one line per log entry, consumed by `MediaCentaur.Console.JournalSource`.

  The Console drawer's "System" tab needs a stream of log lines from
  whatever the OS thinks of as "the service's logs":

  * **Linux** — `journalctl --user -u <unit> -f` reads the systemd
    journal (`Platform.LogSource.Journal`).
  * **macOS** — tails the file paths the launchd plist sets as
    `StandardOutPath` / `StandardErrorPath`
    (`Platform.LogSource.Files`, future phase).

  Only the *spawn* is OS-specific; everything else (subscriber
  fanout, ring buffer, port lifecycle) lives in
  `MediaCentaur.Console.JournalSource` and is platform-agnostic.

  ## Usage

      iex> port = MediaCentaur.Platform.LogSource.open_port("media-centaur.service")
      iex> MediaCentaur.Platform.LogSource.available?("media-centaur.service")
      true

  The facade reads the impl from
  `Application.get_env(:media_centaur, __MODULE__, ...)`, defaulting
  to `Journal`. Tests override via `Application.put_env/3`.
  """

  @callback open_port(unit :: String.t() | nil) :: port()
  @callback available?(unit :: String.t() | nil) :: boolean()

  @doc "Spawn the OS-specific log subprocess and return its `port`."
  @spec open_port(String.t() | nil) :: port()
  def open_port(unit), do: impl().open_port(unit)

  @doc "True when this OS's log source is reachable for `unit`."
  @spec available?(String.t() | nil) :: boolean()
  def available?(unit), do: impl().available?(unit)

  defp impl do
    MediaCentaur.Platform.pick_impl(__MODULE__,
      linux: MediaCentaur.Platform.LogSource.Journal,
      darwin: MediaCentaur.Platform.LogSource.Files
    )
  end
end
