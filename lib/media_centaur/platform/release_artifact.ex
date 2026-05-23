defmodule MediaCentaur.Platform.ReleaseArtifact do
  @moduledoc """
  Knows the tarball naming and GitHub-release URL shape for the
  current OS + architecture.

  The one piece of code in the codebase that switches on `:os.type/0`
  *for the purpose of naming things*. Pure functions; no behaviour.
  All consumers (`SelfUpdate.Updater`, `SelfUpdate.Downloader`, and
  the bundled installer's `--update` mode) read the tarball name
  from here so the literal `linux-x86_64` exists in exactly one
  place.

  ## Supported targets

  * **`linux-x86_64`** — Linux x86_64 (glibc, ubuntu-22.04 builds).
  * **`darwin-arm64`** — macOS Apple Silicon (macos-14 builds).

  Unknown OS or architecture combinations crash loudly rather than
  silently falling back — we'd ship the wrong tarball, which is
  worse than failing the update with a clear error.

  ## Test injection

  `current_platform_tag/1`, `tarball_filename/2`, and `tarball_url/3`
  accept `:os_type` and `:arch` opts so tests can exercise the
  non-runtime branch from a Linux CI runner. Production callers
  use the arity-0 / no-opt forms which read real
  `:os.type/0` + `:erlang.system_info(:system_architecture)`.
  """

  @repo_base "https://github.com/media-centaur/media-centaur/releases/download"

  @doc """
  Platform tag for the running BEAM — used as the `${platform}`
  segment in tarball names and release-asset URLs.
  """
  @spec current_platform_tag(keyword()) :: String.t()
  def current_platform_tag(opts \\ []) do
    os_type = Keyword.get(opts, :os_type, :os.type())
    arch = Keyword.get(opts, :arch, to_string(:erlang.system_info(:system_architecture)))
    detect(os_type, arch)
  end

  @doc """
  Canonical tarball filename for `version` on the current platform.

      iex> MediaCentaur.Platform.ReleaseArtifact.tarball_filename("0.68.1")
      "media-centaur-0.68.1-linux-x86_64.tar.gz"
  """
  @spec tarball_filename(version :: String.t(), keyword()) :: String.t()
  def tarball_filename(version, opts \\ []) do
    "media-centaur-#{version}-#{current_platform_tag(opts)}.tar.gz"
  end

  @doc """
  Canonical GitHub release download URL for `tag` + `version` on
  the current platform.
  """
  @spec tarball_url(tag :: String.t(), version :: String.t(), keyword()) :: String.t()
  def tarball_url(tag, version, opts \\ []) do
    "#{@repo_base}/#{tag}/#{tarball_filename(version, opts)}"
  end

  # --- Private ---

  defp detect({:unix, :linux}, arch) do
    if String.contains?(arch, "x86_64") do
      "linux-x86_64"
    else
      raise "unsupported Linux architecture: #{arch}"
    end
  end

  defp detect({:unix, :darwin}, arch) do
    # `:erlang.system_info(:system_architecture)` varies by macOS
    # version: aarch64-apple-darwin23.4.0 on recent OTP builds,
    # sometimes spelled `arm64-apple-darwin22` on older ones.
    cond do
      String.contains?(arch, "aarch64") -> "darwin-arm64"
      String.contains?(arch, "arm64") -> "darwin-arm64"
      true -> raise "unsupported macOS architecture: #{arch}"
    end
  end

  defp detect(os, arch) do
    raise "unsupported OS for release artifacts: #{inspect(os)} (arch: #{arch})"
  end
end
