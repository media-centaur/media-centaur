defmodule MediaCentaur.Apps.Launcher do
  @moduledoc """
  Fire-and-forget launching of an app's shell command.

  `setsid -f` forks the command into its own session: the intermediate
  process exits immediately, the port closes, and the launched app
  survives Media Centaur restarts. There is no session tracking — for
  Steam URIs the spawned process exits at once anyway (the Steam client
  owns the game), so identical fire-and-forget semantics for every app
  is the only honest contract.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Apps.App

  @doc "The `{executable, argv}` pair `launch/1` spawns. Pure — unit-tested."
  @spec spawn_spec(String.t()) :: {String.t(), [String.t()]}
  def spawn_spec(command) do
    {"setsid", ["-f", "sh", "-c", command]}
  end

  @doc "Spawns the app's command detached. Returns `:ok` or `{:error, :launcher_unavailable}`."
  @spec launch(App.t()) :: :ok | {:error, :launcher_unavailable}
  def launch(%App{} = app) do
    {executable, args} = spawn_spec(app.command)

    case System.find_executable(executable) do
      nil ->
        Log.warning(:apps, "launch failed for #{app.name} — #{executable} not on PATH")
        {:error, :launcher_unavailable}

      path ->
        Port.open({:spawn_executable, to_charlist(path)}, [:binary, args: args])
        Log.info(:apps, "launched #{app.name}")
        :ok
    end
  end
end
