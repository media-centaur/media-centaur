defmodule MediaCentaur.Apps.Launcher do
  @moduledoc """
  Fire-and-forget launching of an app's shell command.

  `setsid -f` forks the command into its own session so the intermediate
  process exits immediately and the port closes — the app runs detached, with
  no session tracking. For Steam URIs the spawned process exits at once anyway
  (the Steam client owns the game), so identical fire-and-forget semantics for
  every app is the only honest contract.

  **Surviving a Media Centaur restart is the OS supervisor's job, not
  setsid's.** Whether the launched app outlives a restart depends entirely on
  the unit's `KillMode`: `KillMode=mixed` SIGKILLs the whole cgroup on stop and
  takes the app with it; `KillMode=process` signals only the BEAM and the app
  survives. Both the prod and dev units run `KillMode=process`. setsid detaches
  the app so it is not a port child to track — it does not, on its own, protect
  the app from the cgroup kill (measured; see
  `campaigns/external-process-lifetime.md` and `MediaCentaur.Playback.MpvSession`).
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
