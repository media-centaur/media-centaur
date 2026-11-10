defmodule MediaCentaur.Console.Supervisor do
  @moduledoc """
  The Console's two processes: `Buffer` (the per-component log rings) and
  `JournalSource` (the systemd journal tail). Independent, `:one_for_one`.
  Started right after PubSub, before the bootstrap, so boot lines reach the
  rings.
  """
  use Supervisor

  alias MediaCentaur.Console

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      Console.Buffer,
      {Console.JournalSource, Application.get_env(:media_centaur, Console.JournalSource, [])}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end
end
