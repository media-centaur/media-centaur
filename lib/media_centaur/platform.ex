defmodule MediaCentaur.Platform do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Authoritative home for every piece of OS-divergent code in Media Centaur.

  **Discoverability rule:** if a module branches on `:os.type/0`,
  shells out to an OS-specific binary (`systemctl`, `launchctl`,
  `journalctl`, `df` with GNU-only flags), or knows the difference
  between Linux and macOS in any structural way, it lives under
  `MediaCentaur.Platform.*`. Nowhere else.

  The `MC0017 PlatformBranchingDiscipline` Credo check enforces
  this mechanically.

  ## Seam inventory

  Each row is one platform-divergence point. Adding a new seam
  means adding a row.

  | Module                          | Kind      | Linux        | macOS       |
  |---------------------------------|-----------|--------------|-------------|
  | `Platform.WatcherEvents`        | pure      | identity     | event remap |
  | `Platform.DriveProbe`           | behaviour | `GnuDf`      | `BsdDf`     |
  | `Platform.LogSource`            | behaviour | `Journal`    | `Files`     |
  | `Platform.Autostart`            | behaviour | `Systemd`    | `Launchd`   |
  | `Platform.ReleaseArtifact`      | pure      | `"linux-x86_64"` | `"darwin-arm64"` |
  | `Platform.Defaults`             | pure      | `/usr/bin/*` | `/opt/homebrew/bin/*` |
  | `Platform.DisplayEnv`           | pure      | Wayland/X11  | `{:ok, []}`  |

  `*(future)*` next to a module name = seam not yet extracted.
  `*(future)*` next to a Linux/macOS impl = that side not yet
  landed but the seam itself exists. See
  `campaigns/macos-platform-support.md` for the rollout plan.

  ## Why a flat namespace

  Each seam is its own module — no god module aggregating
  autostart + drive-probe + log-source into one file. The
  namespace is the inventory; the individual modules carry the
  contracts.

  ## Impl picker

  The only `:os.type/0` call site outside the seam impls themselves.
  `pick_impl/3` is what every behaviour-facade module's private
  `impl/0` calls — it routes between the Linux and macOS impls
  based on the running OS, with an `Application.get_env` override
  for tests.
  """

  @doc """
  Selects the OS-appropriate impl for a Platform.* behaviour.

  Precedence:

  1. `Application.get_env(:media_centaur, facade_module)` — tests
     and runtime config can override.
  2. The matching impl from the `os_impls` keyword list, keyed by
     the running OS (`:linux` / `:darwin`).

  Unrecognized unix-flavored OSes (FreeBSD, NetBSD, ...) fall back
  to the Linux impl on the assumption that GNU-flavored utilities
  are closer; raises on non-unix OSes (Windows isn't a target).

  ## Options

    * `:os_type` — override `:os.type/0` (tests only).
  """
  @spec pick_impl(module(), keyword(), keyword()) :: module()
  def pick_impl(facade_module, os_impls, opts \\ []) do
    case Application.get_env(:media_centaur, facade_module) do
      nil -> default_for_os(os_impls, opts)
      override -> override
    end
  end

  defp default_for_os(os_impls, opts) do
    os_type = Keyword.get(opts, :os_type, :os.type())

    case os_type do
      {:unix, :darwin} -> Keyword.fetch!(os_impls, :darwin)
      {:unix, _other} -> Keyword.fetch!(os_impls, :linux)
      other -> raise "unsupported OS for Platform impl: #{inspect(other)}"
    end
  end
end
