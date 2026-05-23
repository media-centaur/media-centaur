defmodule MediaCentaur.Platform.Defaults do
  @moduledoc """
  OS-aware default paths for external binaries that ship through
  the package manager (mpv, ffprobe).

  Read by `MediaCentaur.Config` at boot — users can still override
  via TOML, so these only matter on first install before the user
  has touched their config file. The Setup Tour's `BinaryDetector`
  already searches the right paths on both OSes (it includes
  `/opt/homebrew/bin` already), so this is purely about the
  zero-config default.
  """

  @doc "Default `mpv` binary path for the current OS."
  @spec mpv_path() :: String.t()
  def mpv_path, do: pick("/usr/bin/mpv", "/opt/homebrew/bin/mpv")

  @doc "Default `ffprobe` binary path for the current OS."
  @spec ffprobe_path() :: String.t()
  def ffprobe_path, do: pick("/usr/bin/ffprobe", "/opt/homebrew/bin/ffprobe")

  defp pick(linux_path, macos_path) do
    case :os.type() do
      {:unix, :darwin} -> macos_path
      _ -> linux_path
    end
  end
end
