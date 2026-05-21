defmodule MediaCentarr.Platform do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Authoritative home for every piece of OS-divergent code in Media Centarr.

  **Discoverability rule:** if a module branches on `:os.type/0`,
  shells out to an OS-specific binary (`systemctl`, `launchctl`,
  `journalctl`, `df` with GNU-only flags), or knows the difference
  between Linux and macOS in any structural way, it lives under
  `MediaCentarr.Platform.*`. Nowhere else.

  The `MC0017 PlatformBranchingDiscipline` Credo check enforces
  this mechanically.

  ## Seam inventory

  Each row is one platform-divergence point. Adding a new seam
  means adding a row.

  | Module                          | Kind      | Linux        | macOS       |
  |---------------------------------|-----------|--------------|-------------|
  | `Platform.WatcherEvents`        | pure      | identity     | event remap |
  | `Platform.Autostart` *(future)* | behaviour | `Systemd`    | `Launchd`   |
  | `Platform.DriveProbe` *(future)*| behaviour | `GnuDf`      | `BsdDf`     |
  | `Platform.LogSource` *(future)* | behaviour | `Journal`    | `Files`     |
  | `Platform.ReleaseArtifact` *(future)* | pure | `"linux-x86_64"` | `"darwin-arm64"` |
  | `Platform.Defaults` *(future)*  | pure      | `/usr/bin/*` | `/opt/homebrew/bin/*` |
  | `Platform.DisplayEnv` *(future)*| pure      | Wayland/X11  | `[]`        |

  Future rows mark the campaign-defined seams that have not yet
  been extracted (see `campaigns/macos-platform-support.md`).

  ## Why a flat namespace

  Each seam is its own module — no god module aggregating
  autostart + drive-probe + log-source into one file. The
  namespace is the inventory; the individual modules carry the
  contracts.
  """
end
