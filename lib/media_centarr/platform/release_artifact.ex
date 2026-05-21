defmodule MediaCentarr.Platform.ReleaseArtifact do
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

  * **`linux-x86_64`** — the only Linux platform the release
    pipeline currently builds for.
  * **`darwin-arm64`** — Apple Silicon. Wired up in a future
    campaign phase; calling on macOS today raises.

  Unknown OS or architecture combinations crash loudly rather than
  silently falling back — we'd ship the wrong tarball, which is
  worse than failing the update with a clear error.
  """

  @repo_base "https://github.com/media-centarr/media-centarr/releases/download"

  @doc """
  Platform tag for the running BEAM — used as the `${platform}`
  segment in tarball names and release-asset URLs.
  """
  @spec current_platform_tag() :: String.t()
  def current_platform_tag do
    detect(:os.type(), to_string(:erlang.system_info(:system_architecture)))
  end

  @doc """
  Canonical tarball filename for `version` on the current platform.

      iex> MediaCentarr.Platform.ReleaseArtifact.tarball_filename("0.68.1")
      "media-centarr-0.68.1-linux-x86_64.tar.gz"
  """
  @spec tarball_filename(version :: String.t()) :: String.t()
  def tarball_filename(version) do
    "media-centarr-#{version}-#{current_platform_tag()}.tar.gz"
  end

  @doc """
  Canonical GitHub release download URL for `tag` + `version` on
  the current platform.
  """
  @spec tarball_url(tag :: String.t(), version :: String.t()) :: String.t()
  def tarball_url(tag, version) do
    "#{@repo_base}/#{tag}/#{tarball_filename(version)}"
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
    # The macOS release artifact lands in a future campaign phase
    # (see `campaigns/macos-platform-support.md`). Crash loudly rather
    # than fall back to a Linux tag we don't have a tarball for.
    raise "macOS release artifacts not yet built (arch: #{arch})"
  end

  defp detect(os, arch) do
    raise "unsupported OS for release artifacts: #{inspect(os)} (arch: #{arch})"
  end
end
