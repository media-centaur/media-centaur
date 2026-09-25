defmodule MediaCentaur.Playback.MpvUserConfig do
  @moduledoc """
  The user's mpv configuration directory, read-only from the app's side.

  The app never writes into it (`LaunchFlags` has the rule). The one thing
  the app wants to know about it: whether it still holds the single-file
  copies of the scripts that are now bundled with the release. mpv
  auto-loads everything in the user config's `scripts/`, so an old copy
  runs alongside the bundled package and every overlay appears twice. The
  session reports them at launch; deleting them is the user's move.
  """

  # The files the pre-bundling guide told users to copy into their config.
  @stale_bundled_names ~w(skip-intro.lua next-episode.lua track-menu.lua)

  @doc """
  mpv's own lookup: `$MPV_HOME`, then `$XDG_CONFIG_HOME/mpv`, then
  `~/.config/mpv`. Takes the environment as a map so the rule is testable.
  """
  @spec dir(%{optional(String.t()) => String.t()}) :: Path.t()
  def dir(env \\ System.get_env()) do
    cond do
      mpv_home = env["MPV_HOME"] -> mpv_home
      xdg = env["XDG_CONFIG_HOME"] -> Path.join(xdg, "mpv")
      true -> Path.join([env["HOME"] || "~", ".config", "mpv"])
    end
  end

  @doc "Paths of old single-file copies of the bundled scripts, sorted; `[]` when clean."
  @spec stale_bundled_copies(Path.t()) :: [Path.t()]
  def stale_bundled_copies(config_dir \\ dir()) do
    scripts_dir = Path.join(config_dir, "scripts")

    @stale_bundled_names
    |> Enum.map(&Path.join(scripts_dir, &1))
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end
end
