---
status: in-progress
started: 2026-05-21
last_updated: 2026-06-10
---
# macOS platform support

## Goal

Ship macOS as a first-class installable platform for Media Centaur
with **full feature parity** — including the in-app self-update
path Linux users have — and **zero regression for Linux**, our
primary demographic.

"Doing this right" is an architectural bar, not a polish bar. The
deliverable is a small, named set of platform seams (behaviours
with one impl per OS) that replace today's implicit Linux
assumptions. Distribution polish (notarization, signed installers,
fancy DMGs) is explicitly out of scope — they don't shape the
architecture.

## Status

**Phases 1–6 shipped (2026-05-21).** All seven Platform.* seams
have both Linux and macOS impls; the impl picker
(`MediaCentaur.Platform.pick_impl/3`) routes them by `:os.type/0`.
CI is green on both `ubuntu-22.04` and `macos-14` with
`--warnings-as-errors` enforced. Phase 6 added the release-side
infrastructure: per-platform overlays under `rel/platforms/`, a
macOS launchd plist + launcher wrapper, a macOS installer script
mirroring the Linux contract, and a `release.yml` matrix that
builds both `linux-x86_64` + `darwin-arm64` tarballs on every tag.
Public-facing READMEs and the docs-site landing carry visible
"UI overhaul in progress" + "macOS — experimental" status banners
(commit `cb0ce0aa`).

**Phase 7 next — real-Mac parity smoke.** Reconciled 2026-06-10:
every tag since v0.72.10 produces both tarballs, and the public
one-line installer supports macOS (Apple Silicon) since
`f85d49c6` / v0.72.10 — the funnel is fully open. **No macOS user
feedback or issues have arrived yet** (zero `macos` issues on the
repo as of v0.87.1). Manual verification of install + in-app
self-update on hardware remains the unknown; we don't own a Mac
(see banner copy); first user reports will substitute.

## Resumption checkpoint

A future session resuming this campaign should:

1. Read this file (`git log` for commit hashes; `Decisions made`
   for the trail).
2. Confirm current `main` is at or past commit `ed4ddf29`
   (release.yml matrix) — that's the campaign's Phase 6 close.
3. Read **"Next steps"** below — only Phase 7 (real-Mac smoke) +
   distribution polish remain.
4. There is no further code work scheduled. The next motion comes
   from a tag (which triggers the new matrix workflow and produces
   the first darwin-arm64 tarball) followed by macOS user feedback.

The architectural posture, audit, divergence analysis, healthy-shape
rules, project-structure visibility, and release-overlay structure
sections below are the *design* — they don't change as phases
ship.

## Architectural posture

Three non-negotiables, in order:

1. **Linux is the trodden path.** Every existing Linux behaviour
   stays byte-identical. The Linux impl of each seam is the
   existing code, lifted unchanged into the new abstraction. We
   do not "refactor Linux to be more portable" — we lift it
   verbatim, then add a second impl beside it.
2. **One seam, one responsibility.** No `Platform` god module
   that owns autostart + log-source + disk-usage in one file.
   Each concern gets its own behaviour/helper module, single
   responsibility, named after what it does (see
   [[architectural-modularity]]).
3. **Platform-divergent code is locatable from `ls`.** Every
   module that knows about OS differences lives under
   `lib/media_centaur/platform/`. The directory itself is the
   discoverability surface — see "Project-structure visibility"
   below.
4. **Parity is proven, not hoped for.** A `macos-14` CI runner
   executes the same test suite as the Linux runner, and a manual
   smoke matrix exercises the un-unit-testable paths (mpv,
   `Updater.apply_pending`, FSEvents watcher) on a real machine.

`case :os.type()` scattered through business modules is the
explicit anti-pattern. It appears only inside
`MediaCentaur.Platform.*` modules, and a Credo check enforces it
(see "Enforcement" below).

## Project-structure visibility

A contributor opening `lib/media_centaur/` for the first time
must be able to answer "where does this app branch on OS?" in
one glance. The answer is: **`lib/media_centaur/platform/`** —
and only there.

### Directory layout

```
lib/media_centaur/
├── platform/                           ← OS-divergent code lives ONLY here
│   ├── platform.ex                     ← inventory + impl picker (the ONE :os.type/0 caller)
│   ├── autostart.ex                    ← behaviour
│   ├── autostart/
│   │   ├── systemd.ex                  ← Linux impl
│   │   └── launchd.ex                  ← macOS impl
│   ├── drive_probe.ex                  ← behaviour
│   ├── drive_probe/
│   │   ├── gnu_df.ex
│   │   └── bsd_df.ex
│   ├── log_source.ex                   ← behaviour
│   ├── log_source/
│   │   ├── journal.ex
│   │   └── files.ex
│   ├── watcher_events.ex               ← pure: translates fsevents+inotify → domain vocab
│   ├── release_artifact.ex             ← pure: tarball naming
│   ├── defaults.ex                     ← pure: mpv/ffprobe paths
│   └── display_env.ex                  ← pure: Wayland/X11 socket scan (returns [] on macOS)
├── self_update/                        ← consumer of Platform.Autostart
├── storage.ex                          ← consumer of Platform.DriveProbe
├── console/                            ← consumer of Platform.LogSource
├── watcher.ex                          ← consumer of Platform.WatcherEvents
└── playback/                           ← consumer of Platform.DisplayEnv
```

### Per-platform release overlays

The same rule applies to release artifacts. Per-platform tarball
contents live under split overlays:

```
rel/
├── platforms/                          ← OS-divergent overlay trees live ONLY here
│   ├── linux/                          ← contents of media-centaur-${ver}-linux-x86_64.tar.gz
│   │   ├── bin/media-centaur-install   (Linux installer; systemd-aware)
│   │   └── share/systemd/media-centaur.service
│   ├── darwin/                         ← contents of media-centaur-${ver}-darwin-arm64.tar.gz
│   │   ├── bin/media-centaur-install   (macOS installer; launchctl-aware)
│   │   ├── bin/media-centaur-launchd-start  (launchd wrapper: loads secrets.env, execs bin/media_centaur)
│   │   └── share/launchd/com.media-centaur.app.plist
│   └── shared/                         ← contents shipped in both
│       └── share/defaults/media-centaur.toml
```

`ls rel/platforms/` → see the platform trees side by side.

**Constraint discovered Phase 6a:** the overlay parent must NOT be
`rel/overlays/`. Mix release's `copy_overlays/1` always prepends
`rel/overlays/` (if it exists) to whatever `:overlays` config you
pass — there is no opt-out. Per-platform subtrees under that path
get double-copied: once stripped via the explicit `:overlays`
config, once with the `linux/`/`darwin/` prefix from the auto-
include. Renaming to `rel/platforms/` defeats the auto-include
while preserving the `ls`-discoverability principle. See
`mix.exs:overlays_for_target/0` and the Phase 6a commit message
for the empirical trace.

### The inventory module

`MediaCentaur.Platform`'s moduledoc lists every platform-seam
module with a one-line description. It is the authoritative
answer to "what diverges?":

```elixir
defmodule MediaCentaur.Platform do
  @moduledoc """
  All platform-divergent code in Media Centaur lives under this
  namespace. Nothing outside `MediaCentaur.Platform.*` may call
  `:os.type/0` or invoke OS-specific binaries directly.

  ## Seams

  | Module | Kind | Linux | macOS |
  |---|---|---|---|
  | `Platform.Autostart`     | behaviour | `Systemd` | `Launchd` |
  | `Platform.DriveProbe`    | behaviour | `GnuDf`   | `BsdDf` |
  | `Platform.LogSource`     | behaviour | `Journal` | `Files` |
  | `Platform.WatcherEvents` | pure      | identity  | `:removed→:deleted`, `:unmount→:unmounted`, etc. |
  | `Platform.ReleaseArtifact` | pure    | `"linux-x86_64"` | `"darwin-arm64"` |
  | `Platform.Defaults`      | pure      | `/usr/bin/...` | `/opt/homebrew/bin/...` |
  | `Platform.DisplayEnv`    | pure      | Wayland/X11 scan | `[]` |

  See each module's moduledoc for the contract.
  """
end
```

That table is the source of truth. Adding a new seam means
adding a row.

### Enforcement (Credo)

A custom Credo check — `MC00NN PlatformBranchingDiscipline` —
fails the build on:

* `:os.type/0` or `:os.cmd/1` calls outside `MediaCentaur.Platform.*`
* `System.cmd/3` to known OS-specific binaries (`systemctl`,
  `launchctl`, `journalctl`, `df` when invoked with GNU-only
  flags) outside `MediaCentaur.Platform.*`
* New `:linux-x86_64` / `:darwin-arm64` literals outside
  `Platform.ReleaseArtifact`

This follows the established project pattern (`MC0008 TypedComponentAttrs`,
`MC0009 StorybookCoverage`, `MC0016 RenderingDefaults`). The check
keeps the architectural rule mechanical, not aspirational.

## Audit — surfaces that assume Linux

Each entry is paired with the seam it will live behind (next
section).

| Where today | What | Lands at |
|---|---|---|
| `mix.exs:16-23` | `include_executables_for: [:unix]` — covers macOS already | — |
| `.github/workflows/release.yml` | Builds `linux-x86_64` only, ubuntu-22.04 | CI matrix |
| `rel/overlays/bin/media-centaur-install` | Linux x86_64 glibc, sha256sum, GNU readlink, systemd | `rel/overlays/linux/` (split from current `rel/overlays/`) |
| `lib/media_centaur/self_update/service.ex` | systemd via `INVOCATION_ID` + `systemctl --user` + `/proc/self/cgroup` | `Platform.Autostart` + `Platform.Autostart.Systemd` |
| `lib/media_centaur/self_update/handoff.ex` | XDG_RUNTIME_DIR + DBUS_SESSION_BUS_ADDRESS pass-through; `setsid --fork` (GNU) | Env list moves into `Platform.Autostart.handoff_env_vars/0`; detach idiom made portable |
| `lib/media_centaur/self_update/stager.ex` | Required path `share/systemd/media-centaur.service` | Required paths come from `Platform.Autostart.tarball_required_paths/0` |
| `lib/media_centaur/self_update/updater.ex:319` + `downloader.ex:24` | `linux-x86_64` literal | `Platform.ReleaseArtifact` |
| `lib/media_centaur/storage.ex` | GNU `df --output=…` | `Platform.DriveProbe` + `Platform.DriveProbe.GnuDf` |
| `lib/media_centaur/playback/display_env.ex` | Wayland/X11 socket scan | `Platform.DisplayEnv` (pure, OS branch inside) |
| `lib/media_centaur/console/journal_source.ex` | Reads `journalctl` | `Platform.LogSource` + `Platform.LogSource.Journal` |
| `lib/media_centaur/config.ex:424,427` | `/usr/bin/mpv`, `/usr/bin/ffprobe` defaults | `Platform.Defaults` |
| `lib/media_centaur/watcher.ex:196,209` | Matches `:unmounted` + `:deleted` — Linux inotify vocabulary; FSEvents emits `:unmount` + `:removed` | `Platform.WatcherEvents` |

## Concrete divergences (the real engineering)

What follows is the actual OS-level divergence behind each seam,
not the surface "systemd vs launchd" hand-wave. Each subsection
ends with the behaviour-contract shape that contains it.

### Autostart — process supervision differs in five places

| Concern | Linux (systemd) | macOS (launchd) |
|---|---|---|
| "Am I under supervision?" | `INVOCATION_ID` env var set by systemd | `launchctl print pid/$$` returns success when parented by launchd in a known domain. PID 1 is launchd system-wide so PPID==1 isn't sufficient |
| Unit name discovery | Parse `/proc/self/cgroup` for `*.service` suffix | Read the `Label` from the launchd job (`launchctl print pid/$$` output). cgroups don't exist on macOS |
| Default unit identifier | `media-centaur.service` | `com.media-centaur.app` (reverse-DNS label per Apple convention) |
| Unit-file format | INI `[Unit] [Service] [Install]` | XML plist with `Label`, `ProgramArguments`, `KeepAlive`, `ThrottleInterval`, `StandardOutPath`, `StandardErrorPath` |
| Domain & install location | `~/.config/systemd/user/` | `~/Library/LaunchAgents/` |
| Restart | `systemctl --user --no-block restart unit` (queued; returns immediately so caller doesn't deadlock on its own death) | `launchctl kickstart -k gui/$UID/com.media-centaur.app` (`-k` sends SIGTERM then restarts) |
| Stop | `systemctl --user stop unit` (active→inactive, autostart pref preserved) | `launchctl disable gui/$UID/com.media-centaur.app` + `launchctl bootout gui/$UID com.media-centaur.app` (two-step: KeepAlive=true would otherwise restart) |
| Enable+start (install) | `systemctl --user enable --now unit` | `launchctl bootstrap gui/$UID ~/Library/LaunchAgents/foo.plist` + `launchctl enable gui/$UID/com.media-centaur.app` + `launchctl kickstart gui/$UID/com.media-centaur.app` |
| Status output | `systemctl --user status unit --no-pager` (human-readable, well-formed) | `launchctl print gui/$UID/com.media-centaur.app` (structured but very different shape) |
| Env handover to detached child | Must forward `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, `XDG_DATA_DIRS`, `XDG_CONFIG_DIRS` to reach the user's systemd | `launchctl gui/$UID` is resolved from caller's UID; no env handover needed (assuming caller is in the user's Aqua session) |
| Logging | stdout/stderr → journald automatically; `journalctl --user -u unit` reads it | We set `StandardOutPath` + `StandardErrorPath` in the plist; logs land in files we control |

**Behaviour contract** — `MediaCentaur.Platform.Autostart`:

```
@callback state() :: %{under_supervision: boolean(),
                       available: boolean(),
                       unit: String.t() | nil,
                       unit_installed: boolean(),
                       active: boolean(),
                       enabled: boolean()}
@callback detect_unit() :: String.t() | nil
@callback restart() :: :ok | {:error, term()}
@callback stop()    :: :ok | {:error, term()}
@callback status_output() :: {:ok, String.t()} | {:error, term()}

# Used by SelfUpdate.Handoff to forward the env vars THIS autostart
# system needs through `env -i`. Empty list = no handover required.
@callback handoff_env_vars() :: [String.t()]

# Used by SelfUpdate.Stager to validate incoming release tarballs
# contain THIS autostart system's unit-file.
@callback tarball_required_paths() :: [String.t()]
```

The handoff-env list is autostart knowledge — moving it into
`Handoff` would couple `Handoff` to systemd. Keep it on the
behaviour where it belongs.

**Linux impl** (`Platform.Autostart.Systemd`): lift `SelfUpdate.Service`
body verbatim. `handoff_env_vars/0` returns
`["XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "XDG_DATA_DIRS", "XDG_CONFIG_DIRS"]`.
`tarball_required_paths/0` returns
`["share/systemd/media-centaur.service"]`.

**macOS impl** (`Platform.Autostart.Launchd`): new module wrapping `launchctl`.
`handoff_env_vars/0` returns `[]`. `tarball_required_paths/0`
returns `["share/launchd/com.media-centaur.app.plist"]`.

**What MUST NOT leak into this behaviour:** download URLs, tarball
filenames, mpv paths, drive probing, log reading. If you find
yourself adding any of those, you've chosen the wrong seam.

### Watcher — file_system backends emit different event vocabularies

The bug-shaped divergence. `file_system` library transparently
picks `FSInotify` (Linux) or `FSMac` (macOS), but the event atoms
in `{:file_event, pid, {path, events}}` differ:

| Domain meaning | inotify atom | FSEvents atom |
|---|---|---|
| File created | `:created` | `:created` |
| File written to | `:modified` | `:modified` |
| **File deleted** | `:deleted` | **`:removed`** |
| **Volume unmounted** | `:unmounted` | **`:unmount`** |
| File renamed | (delete + create pair) | `:renamed` |
| Metadata change | (none) | `:inodemetamod`, `:finderinfomod`, `:xattrmod`, `:changeowner` |
| FSEvents-specific signals | — | `:mustscansubdirs`, `:userdropped`, `:kerneldropped`, `:eventidswrapped`, `:rootchanged` |

Our `Watcher.handle_info({:file_event, _pid, {path, events}}, state)`
matches `:unmounted in events` and `:deleted in events` — on macOS
**neither would fire**. Deletes would silently propagate as nothing;
unmounts wouldn't transition to `:unavailable`. Both are
parity-breaking.

**Seam**: a tiny pure helper `MediaCentaur.Platform.WatcherEvents`
sitting between `file_system` and the `Watcher` business logic.
It collapses both backend vocabularies into our four domain atoms
(`:created | :modified | :deleted | :unmounted`) plus optionally a
`:scan_required` for FSEvents' `:mustscansubdirs` / `:userdropped`
/ `:kerneldropped` advisory signals. The macOS-only signals don't
have inotify analogs — they degrade to `:scan_required`, which the
Watcher already knows how to handle (it triggers `:auto_scan`).

**Behaviour contract** — pure module, no `@behaviour` needed:

```
@spec normalize([atom()]) :: [normalized_event]
@type normalized_event :: :created | :modified | :deleted | :unmounted | :scan_required
```

The Watcher applies `Platform.WatcherEvents.normalize/1` once on
receipt and matches only on the normalized atoms thereafter. The
backend-specific atoms are quarantined to the helper, which lives
under `lib/media_centaur/platform/` alongside every other piece of
OS-divergent code.

**Two additional macOS-specific constraints discovered:**

1. `priv/mac_listener` is a **per-platform compiled binary** that
   `file_system` requires on macOS. Hex ships pre-compiled, but it
   must end up in the release tarball — which means **the macOS
   tarball cannot be cross-compiled from Linux**. Forces a real
   macos-14 CI runner.
2. APFS is **case-insensitive by default**. Our `interesting?/2`
   and `VideoFile.video?/1` already lowercase the extension, but
   any code path that compares two filenames by exact case would
   misbehave. Audit needed — likely fine, but worth a grep pass.

### DriveProbe — `df` is GNU-only

| | Linux (GNU df) | macOS (BSD df) |
|---|---|---|
| Bytes-level output | `df --output=source,used,avail,target -B1 PATH` (explicit columns, bytes-not-blocks) | `df -k -P PATH` (POSIX format, 1024-blocks, multiply by 1024) |
| Wraparound prevention | not needed with `--output=` | `-P` (POSIX) prevents column wrap on long device names |
| Column order | controlled via `--output=` | fixed: Filesystem, 1024-blocks, Used, Available, Capacity, Mounted on |

**Behaviour contract** — `MediaCentaur.Platform.DriveProbe`:

```
@callback available_bytes(Path.t()) :: {:ok, non_neg_integer()} | :error
@callback measure(Path.t()) :: {:ok, drive_info()} | :error
```

`Storage.measure_all` becomes a pure aggregator over `DriveProbe`
calls. No shell-out inside `Storage` itself.

**Linux impl** (`Platform.DriveProbe.GnuDf`): lift current body.
**macOS impl** (`Platform.DriveProbe.BsdDf`): `df -k -P` parser;
multiply 1024-blocks by 1024.

### LogSource — journald vs files we write

| | Linux | macOS |
|---|---|---|
| Source | journald, queried via `journalctl --user -u unit` | files we configure in the plist (`StandardOutPath`, `StandardErrorPath`) |
| Metadata | structured (`_SYSTEMD_UNIT`, `_PID`, priority, timestamps) | line-oriented, plain text |
| Filtering | `--since`, `--priority`, `--grep` | tail + in-process filtering |

**Important**: because we *write* the plist, **we choose** the log
paths on macOS — e.g., `~/Library/Logs/Media Centaur/stdout.log`
+ `stderr.log`. That gives us a real `LogSource.Files` impl that
provides parity with the Linux "System" Console tab, not the
`Noop` fallback I sketched in v1 of this doc.

**Behaviour contract** — `MediaCentaur.Platform.LogSource`:

```
@callback available?() :: boolean()
@callback tail(count :: pos_integer()) :: {:ok, [entry()]} | {:error, term()}
@callback stream(opts :: keyword()) :: Enumerable.t()
```

**Linux impl** (`Platform.LogSource.Journal`): lift current
`Console.JournalSource` body. **macOS impl**
(`Platform.LogSource.Files`): tail the launchd-configured log
files. Same drawer behaviour, different source.

### ReleaseArtifact — the one place that knows the platform tag

The only module in the codebase that switches on `:os.type/0`
**for the purpose of naming things**. Pure functions; no behaviour.

```
defmodule MediaCentaur.Platform.ReleaseArtifact do
  @spec current_platform_tag() :: String.t()
  def current_platform_tag, do: pick(:os.type(), :erlang.system_info(:system_architecture))

  defp pick({:unix, :linux}, arch),  do: detect_linux_arch(arch)   # "linux-x86_64"
  defp pick({:unix, :darwin}, arch), do: detect_darwin_arch(arch)  # "darwin-arm64"
  # Unknown OS → crash. Don't silently fall back; we'd ship the wrong tarball.

  @spec tarball_filename(version :: String.t()) :: String.t()
  def tarball_filename(version),
    do: "media-centaur-#{version}-#{current_platform_tag()}.tar.gz"

  @spec tarball_url(tag :: String.t(), version :: String.t()) :: String.t()
end
```

Consumers (`Updater`, the installer's `--update` mode) get the
filename from here. The literal `linux-x86_64` no longer appears
anywhere else.

### Platform.Defaults — OS-aware mpv/ffprobe paths

Single helper, OS branching inside, used only by `Config` at boot.
Trivial; not a behaviour. Linux returns `/usr/bin/...`, macOS
returns `/opt/homebrew/bin/...`. `BinaryDetector` already searches
the right paths for the Setup Tour.

### Spawn / detach mechanism — POSIX, but BSD vs GNU

`SelfUpdate.Handoff` uses `setsid --fork sh -c '...' -- $installer $log`
to spawn a detached grandchild. BSD `setsid` (macOS) doesn't have
`--fork` — but also doesn't need it; it forks by default. And
macOS doesn't always ship `setsid` at `/usr/bin/setsid` (depends on
OS version; recent macOS does).

Two clean options:

* **Move to a portable detach idiom**: `sh -c '(exec "$1" >"$2" 2>&1 &) ; disown' --`
  works on both. The current `Port.open(..., :nouse_stdio)` already
  handles the SIGPIPE concern.
* **OS-specific detach prefix** behind a tiny helper at
  `lib/media_centaur/platform/spawn.ex` returning
  `["setsid", "--fork"]` on Linux, `["setsid"]` on macOS (or `[]`
  if we go with the portable idiom).

The portable idiom is preferable — it eliminates a seam rather
than adding one. Same rule applies as everywhere else: don't
abstract what doesn't actually differ. Verify behaviour-equivalent
under load; if it is, no seam, just a small `Handoff` cleanup.

### DisplayEnv — pure module, OS branch inside

`Playback.DisplayEnv` today scans `$XDG_RUNTIME_DIR/wayland-N` and
`/tmp/.X11-unix/XN` to inject Wayland/X11 env into the mpv
subprocess. On macOS mpv uses the native Cocoa backend; no socket
discovery needed.

Even though the divergence is tiny (one OS gate, body unchanged
otherwise), the rule "OS-divergent code lives under `platform/`"
applies — so the module **moves** to `Platform.DisplayEnv`. The
body is the existing Linux scan; the function returns `[]` early
on macOS. Not a behaviour (single shape, no impl polymorphism),
not a `case` scattered through `Playback` — a named seam in the
right directory.

### Paths (XDG) — the deliberate non-seam

Linux uses XDG Base Directory Spec
(`~/.config`, `~/.local/share`, `~/.cache`). macOS Apple HIG would
prefer `~/Library/Application Support`, `~/Library/Caches`,
`~/Library/Logs`. XDG paths **work** on macOS — they just look
non-native to Finder users.

**Decision (proposed)**: stay on XDG on both. Reasoning:
* One code path, one test fixture tree, one set of docs.
* `MEDIA_CENTAUR_CONFIG_DIR` / `_DATA_DIR` / `_CACHE_DIR` env
  overrides exist and work on both, so users who want Apple HIG
  paths set them themselves.
* Adding a `Paths` behaviour for one cosmetic divergence is the
  textbook YAGNI violation.
* If user feedback later demands Apple HIG defaults, the seam is
  trivially added — until then, no abstraction earns its weight.

Document this as an explicit decision (not an oversight) in the
ADR.

## The healthy-shape rules

What would corrupt each seam if added — name the anti-patterns so
future contributors don't trip into them.

1. **One directory.** Every module that diverges on OS lives
   under `lib/media_centaur/platform/`. Nothing OS-specific lives
   anywhere else. `ls lib/media_centaur/` makes this discoverable.
2. **`Platform` is a namespace, not a module.** There is no
   single file aggregating autostart + drive-probe + log-source.
   `MediaCentaur.Platform` itself is a thin doc-only module
   carrying the seam inventory and the impl picker. Each seam is
   its own module under the namespace.
3. **No business-module OS branching.** `case :os.type/0` and
   OS-conditional `System.cmd/3` calls appear *only* inside
   `MediaCentaur.Platform.*`. They NEVER appear in `Library`,
   `Acquisition`, `Watcher`, `SelfUpdate`, `Storage`, `Console`,
   `Playback`, or any LiveView. The `MC00NN` Credo check enforces
   this mechanically.
4. **No cross-seam knowledge.** `Platform.Autostart` doesn't know
   the download URL. `Platform.ReleaseArtifact` doesn't know the
   autostart format. `Platform.LogSource` doesn't know how to
   restart the service. If you find yourself reaching from one
   seam into another, you've drawn the boundary wrong.
5. **No leaking impl vocabulary into consumers.** `Watcher` works
   on `:created | :modified | :deleted | :unmounted`, never on
   `:removed` or `:unmount`. `Platform.WatcherEvents` is the only
   place that knows the backend atoms exist.
6. **Lift, don't refactor.** The Linux impl of each seam is the
   existing code, verbatim, in a renamed module under `platform/`.
   Phase 1 diffs should be pure code motion — no logic edits.
   This is the contract that protects Linux from regression.
7. **OS detection is configuration, not control flow.** The picker
   in `MediaCentaur.Platform.pick/1` reads `:os.type/0` at boot and
   writes the chosen impl into application config. Consumers read
   `Application.fetch_env!(:media_centaur, Platform.Autostart)` and
   call `mod.foo()`. Tests override via config — no recompile, no
   env-var hacks, no `case` in hot paths.

## Release-overlay structure

Per-platform tarballs require per-platform release overlays.

**Phase-6a discovery:** mix `releases:` cannot be split into
`media_centaur_linux` + `media_centaur_darwin` entries the way the
original design proposed — release name controls binary name, so a
`media_centaur_linux` release would produce `bin/media_centaur_linux`,
breaking every existing install whose self-updater expects
`bin/media_centaur` and breaking `SelfUpdate.Stager`'s required-paths
contract. Cross-version self-update would silently fail to find the
binary in the new tarball.

The shipped design is a single `media_centaur` release entry with
OS-aware overlays selected at evaluation time:

```elixir
releases: [
  media_centaur: [
    include_executables_for: [:unix],
    overlays: overlays_for_target()
  ]
]

defp overlays_for_target do
  shared = "rel/platforms/shared"

  per_os =
    case :os.type() do
      {:unix, :darwin} -> "rel/platforms/darwin"
      {:unix, _} -> "rel/platforms/linux"
    end

  Enum.filter([shared, per_os], &File.dir?/1)
end
```

`mix release` runs natively on each target OS (`priv/mac_listener`
is a per-platform binary that forces this), so `:os.type/0` at
mix-evaluation time equals the build target. Same `bin/media_centaur`
on both platforms; the OS-specific autostart unit-file +
installer ride in via the overlays.

Each overlay tree contains its own:
* `bin/media-centaur-install` (platform-specific installer)
* `share/<autostart-system>/<unit-file>` (systemd unit or
  launchd plist; macOS also ships `bin/media-centaur-launchd-start`
  as the LaunchAgent's entry-point wrapper)
* `share/defaults/media-centaur.toml` (identical between platforms,
  lives under `rel/platforms/shared/`)

CI runs `mix release` on `ubuntu-22.04` and on `macos-14` in a
matrix, emitting both tarballs (and a consolidated `SHA256SUMS`)
to the same GitHub Release via a separate `release` job that
depends on the matrix. No cross-compilation, no inline-create
race (the previous design's `gh release create` would have raced
when two matrix jobs landed simultaneously).

## Linux non-regression guarantees

Concrete, checkable, must hold at every phase merge:

* `Platform.Autostart.Systemd` is the current `SelfUpdate.Service`
  body relocated under `lib/media_centaur/platform/autostart/` —
  no logic edits. A diff review on phase 2 must show
  `Service` → `Platform.Autostart.Systemd` as pure code motion.
* The Linux tarball (`media-centaur-${ver}-linux-x86_64.tar.gz`)
  contains the same file tree it does today. `Stager`'s required
  paths for Linux remain
  `["bin/media-centaur-install", "bin/media_centaur", "share/systemd/media-centaur.service", "share/defaults/media-centaur.toml"]`.
* `bin/media-centaur-install` in the Linux tarball is byte-for-byte
  identical until phase 2 lands the single `ReleaseArtifact`-based
  tarball-name lookup. That change is one line in the installer's
  `--update` mode, reviewed in isolation.
* Every phase ships independently on the normal `/ship` cadence,
  with `mix precommit` green and the existing Linux smoke matrix
  green. No "macOS phase" lands a Linux behaviour change.
* `Platform.WatcherEvents.normalize/1` on Linux atom input is the
  identity function on `:created | :modified | :deleted | :unmounted`.
  A property test proves it.

## Open decisions (block ADR, in order)

*All Phase-1 architecture decisions are resolved by the shipped
work. Kept here as a record of the framing that drove the design.*

1. ~~**Architecture lock-in.**~~ **Resolved**: shipped exactly the
   seam map proposed — 3 behaviours (`Autostart`, `DriveProbe`,
   `LogSource`) + 4 pure helpers (`WatcherEvents`,
   `ReleaseArtifact`, `Defaults`, `DisplayEnv`) + 1 picker
   (`MediaCentaur.Platform`). Deliberate non-seams (`Paths`,
   `Spawn`) stayed inline. `MC0017 PlatformBranchingDiscipline`
   enforces the discoverability rule.
2. ~~**Architectures.**~~ **Resolved**: Apple Silicon only.
   `ReleaseArtifact` raises on Intel macOS (`x86_64-apple-darwin`).
   Adding Intel later means one new clause in `detect/2` plus a
   `macos-13` release-job, no further design change.

**Still deferred (Phase 6+):**

* Distribution channel (Homebrew tap, raw tarball + install.sh,
  notarized .pkg). The user has explicitly said notarization /
  signing polish is out of scope. Likely: raw tarball + install.sh
  for parity with Linux, no Homebrew tap until there's user demand.

## Decisions made

Append-only log.

* `2026-05-21` — **Phases 1–5 shipped.** Linux Platform.* directory
  (Phase 1, `bc156933`); Linux extractions Autostart + DriveProbe +
  LogSource (Phase 2, three commits `ea88f5cb`/`3a28cc06`/`fadc5d9e`);
  ReleaseArtifact + Defaults + DisplayEnv (Phase 3, `6b596f81`);
  macOS CI gate (Phase 4, `765b9ef0` + fixes); macOS impls
  (Phase 5: `6ca6bea5` ReleaseArtifact darwin-arm64, `0d9f341a`
  DriveProbe.BsdDf, `32f7852c` Autostart.Launchd, `069ccbcd`
  LogSource.Files, `06ca739f` Platform.pick_impl). All seven
  Platform.* seams now have both Linux + macOS impls. CI green
  across both runners with `--warnings-as-errors` enforced
  (typo restored in `9528cc1b`).
* `2026-05-21` — **`test-isolation-hardening` campaign closed
  mid-Phase-4.** A side campaign harvested four categories of
  pre-existing test flake the macOS strict-flag exposed:
  Category A (on_exit DB writes — MC0018 Credo check), B (async
  Task DB ownership — DataCase drain), D (NoDbOnRender budget),
  E (Config persistent_term cache — DataCase snapshot+restore).
  (Campaign completed and removed per ADR-042 — see git history.)
* `2026-05-21` — **Phase 6 shipped.** Per-platform release-artifact
  infrastructure landed in four narrow commits:
  * `8ac48f89` — overlay restructure under `rel/platforms/{linux,shared}/`
    + `mix.exs:overlays_for_target/0`. Linux tarball byte-equivalent.
  * `fe45f0f5` — macOS launchd plist + `bin/media-centaur-launchd-start`
    wrapper (loads `secrets.env`, exec's `bin/media_centaur` —
    the launchd analog of systemd's `EnvironmentFile=`).
  * `ae7f18e8` — macOS installer script mirroring the Linux
    contract (`--update`/`--uninstall`/service install|remove,
    atomic symlink flip, tag-injection guard, sha256/shasum
    fallback for the macOS base install).
  * `ed4ddf29` — `release.yml` matrix builds both `linux-x86_64`
    + `darwin-arm64` on native runners; consolidated SHA256SUMS
    + atomic publish via separate `release` job that depends on
    the matrix.

  **Two constraint discoveries** updated the original design:
  1. **Mix auto-prepends `rel/overlays/`** to every release's
     overlay list (`Mix.Tasks.Release.copy_overlays/1`, no opt-out).
     Per-platform subtrees under that path got double-copied —
     once stripped via the explicit `:overlays` config, once with
     the `linux/`/`darwin/` prefix from the auto-include. Renamed
     parent to `rel/platforms/` to defeat the auto-include while
     preserving `ls`-discoverability.
  2. **Mix release name controls binary name** — splitting
     `releases:` into `media_centaur_linux` + `media_centaur_darwin`
     (the original design) would have produced
     `bin/media_centaur_linux`, breaking every existing install's
     self-updater + `SelfUpdate.Stager`'s required-paths contract.
     Single `media_centaur` release entry with `overlays_for_target/0`
     selecting per-OS overlays at evaluation time keeps
     `bin/media_centaur` stable across both platforms.

* `2026-06-10` — **Public installer supports macOS** (`f85d49c6`,
  v0.72.10): `curl … install.sh | sh` detects Apple Silicon and
  installs the darwin-arm64 tarball — Phase 7's funnel needs no
  further plumbing, only a user with hardware.

## Next steps

Phases 1–6 are **done**; see the "Decisions made" log above for
commit hashes. Only manual real-machine smoke + downstream
distribution polish remain.

1. **Phase 7 — Parity smoke (manual, real machine).** The next
   tag will trigger the matrix workflow and produce both
   `media-centaur-${ver}-linux-x86_64.tar.gz` and
   `media-centaur-${ver}-darwin-arm64.tar.gz`. First Mac user
   reports substitute for our lack of hardware. The README +
   docs-site `[macOS]` issue link is the funnel. Track findings
   here as the campaign re-opens with them. Key things to verify:
   * Tarball downloads, extracts, `bin/media-centaur-install`
     runs to completion.
   * LaunchAgent registers; the app starts and listens on the
     configured port; logs land in `~/Library/Logs/Media Centaur/`.
   * Settings → Overview → Update now exercises the full
     `Platform.Autostart.Launchd.restart/0` path end-to-end.
   * `file_system` (FSEvents) emits events the Watcher receives
     (and `Platform.WatcherEvents.normalize/1` translates them
     to the domain vocabulary correctly).
2. **Distribution polish.** Decide raw tarball + install.sh (parity
   with Linux) vs Homebrew tap based on Phase-7 feedback. The user
   has explicitly ruled out notarization for now.

## Completion criteria

* A macOS arm64 user installs, runs, and uses the in-app
  Settings → Overview → Update now flow without manual `xattr`
  workarounds or terminal intervention beyond the initial
  install command.
* No `case :os.type/0` (or equivalent) appears in any business
  module — only inside platform-seam impls or the impl picker.
* Linux behaviour is provably unchanged: existing tests
  unchanged, existing systemd autostart unchanged, existing
  installer script unchanged through phase 2 (and changed only
  by the one-line `ReleaseArtifact` lookup in phase 3).
* CI runs the suite on both `ubuntu-22.04` and `macos-14` on
  every PR, and both gate `mix precommit`.
* Library, Acquisition Pursuits, mpv playback, file watcher
  (with deletes + unmounts firing via `EventNormalizer`), and
  self-update all work on macOS — verified by phase 7 smoke.

## Pointers

### Lands at

* `lib/media_centaur/platform/` (new directory)
* `lib/media_centaur/platform/platform.ex` — inventory moduledoc + impl picker
* `lib/media_centaur/platform/autostart.ex` + `autostart/systemd.ex` + `autostart/launchd.ex`
* `lib/media_centaur/platform/drive_probe.ex` + `drive_probe/gnu_df.ex` + `drive_probe/bsd_df.ex`
* `lib/media_centaur/platform/log_source.ex` + `log_source/journal.ex` + `log_source/files.ex`
* `lib/media_centaur/platform/watcher_events.ex`
* `lib/media_centaur/platform/release_artifact.ex`
* `lib/media_centaur/platform/defaults.ex`
* `lib/media_centaur/platform/display_env.ex`
* `credo_checks/platform_branching_discipline.ex` — `MC00NN` check
* `rel/platforms/{linux,darwin,shared}/` — split per-platform overlays
  (NOT `rel/overlays/` — see Phase-6a discovery in `Decisions made`)
* `rel/platforms/darwin/share/launchd/com.media-centaur.app.plist` — LaunchAgent
* `rel/platforms/darwin/bin/media-centaur-launchd-start` — launchd entry-point wrapper
* `rel/platforms/darwin/bin/media-centaur-install` — macOS installer

### Lifts from

* `lib/media_centaur/self_update/service.ex` → `Platform.Autostart.Systemd`
* `lib/media_centaur/self_update/handoff.ex` → handoff env list moves into `Platform.Autostart.handoff_env_vars/0`; portable detach idiom replaces `setsid --fork` inline
* `lib/media_centaur/self_update/stager.ex` → `:required` = base list + `Platform.Autostart.tarball_required_paths/0`
* `lib/media_centaur/self_update/updater.ex:319` + `downloader.ex:24` → `Platform.ReleaseArtifact`
* `lib/media_centaur/storage.ex` → `Platform.DriveProbe.GnuDf` + thin `Storage` aggregator
* `lib/media_centaur/console/journal_source.ex` → `Platform.LogSource.Journal`
* `lib/media_centaur/playback/display_env.ex` → `Platform.DisplayEnv`
* `lib/media_centaur/config.ex:424,427` → reads `Platform.Defaults`
* `lib/media_centaur/watcher.ex:196,209` → matches normalized vocabulary from `Platform.WatcherEvents`

### External references

* `deps/file_system/lib/file_system/backends/fs_mac.ex:73-95` — upstream event vocabulary we're normalizing away from
* `mix.exs:16-23` — release config; will split into per-platform releases
* `.github/workflows/ci.yml`, `.github/workflows/release.yml` — matrix expansion
