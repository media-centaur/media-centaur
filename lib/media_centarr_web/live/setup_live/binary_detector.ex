defmodule MediaCentarrWeb.Live.SetupLive.BinaryDetector do
  @moduledoc """
  Auto-detects executable binaries at common Linux/macOS install paths.

  Used by the Setup Tour to suggest paths for `mpv`, `ffprobe`, etc.
  Returns the de-duplicated list of paths that exist on disk for a given
  binary name.

  Pure function — no config reads, no side effects. Tests inject their
  own search paths via `detect/2`.
  """

  @common_paths [
    "/usr/bin",
    "/usr/local/bin",
    "/opt/homebrew/bin",
    "/snap/bin",
    "~/.local/bin"
  ]

  @doc "Returns existing paths for `name` across the default common paths."
  @spec detect(String.t()) :: [String.t()]
  def detect(name) when is_binary(name), do: detect(name, @common_paths)

  @doc "Returns existing paths for `name` across the given search paths."
  @spec detect(String.t(), [String.t()]) :: [String.t()]
  def detect(name, paths) when is_binary(name) and is_list(paths) do
    via_path = System.find_executable(name)

    [via_path | Enum.map(paths, &Path.join(Path.expand(&1), name))]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.filter(&File.regular?/1)
  end
end
