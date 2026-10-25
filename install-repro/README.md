# Install reproduction

Scripted install paths for Media Centaur, run against real operating systems
so an installer fault can be proven, fixed and kept fixed. A **scenario** is
one script that runs one install path and ends in pass or fail. It checks the
outcome itself — the service manager, the HTTP port, the logs — not the
installer's summary.

## Layout

```
install-repro/scenarios/
├── lib                  shared helpers; sources <platform>/platform
├── sudo-refused …       the shared scenarios, one per install path
├── macos/               launchd adapter, disabled-service, environment, collect-evidence
└── linux/               systemd adapter, disabled-service, environment, collect-evidence
```

Each scenario is written once. `<platform>/platform` answers the
service-manager questions for it (`launchctl` on macOS, `systemctl --user` on
Linux). Only the disabled-service scenario differs by platform, because the
two installers follow different rules (see below).

## Scenarios

| Scenario | What it proves |
|---|---|
| `sudo-refused` | Both installers refuse `sudo` and write nothing. Needs a clean machine, so it runs first. |
| `fresh-install` | The public installer, run without `sudo`, ends with the service set to start at login, running, and the app answering on port 2160. |
| `reinstall` | Running the installer again over a running install leaves the service running. |
| `<platform>/disabled-service` | macOS: an install over a disabled label re-enables and loads it. Linux: an install over a disabled unit keeps it off and says so; `service install` turns it back on. |
| `manual-start` | With the service stopped, `bin/media_centaur daemon` boots the app with `secrets.env` loaded; `service install` restores autostart. |
| `uninstall` | The app and the service are gone, nothing starts at login, and config and data are kept. |
| `upgrade` | Installing the tag over the release before switches `current` to it, and the running app reports the new version. |
| `fresh-install-log` | The fresh install logged no `[error]` line. |
| `in-app-update` | From the release before, the update the Settings button starts reaches the latest release, and the running app reports it. |

The lifecycle job runs the first eight in order, each building on the state
the one before left. `in-app-update` runs in its own job on a clean runner. It
always updates to GitHub's latest release, so it tests the tag under test only
when that tag is the latest — run without a tag to test the latest release. A
runner's shared IP often has used up GitHub's API limit; the scenario waits
for the reset once. Each job uploads `collect-evidence` output (app logs,
update handoff logs, service-manager state) as an artifact.

## Environments

| Platform | Runner | Service manager |
|---|---|---|
| macOS | `macos-14` (Apple Silicon) | an Aqua `gui/501` launchd domain |
| Linux | `ubuntu-24.04` | a lingering systemd user manager for `runner` |

## Running it

By hand, when we decide to — nothing triggers it automatically:

```sh
gh workflow run install-repro.yml                              # latest release, both platforms
gh workflow run install-repro.yml -f tag=v1.60.3 -f platform=linux
gh workflow run install-repro.yml -f source=branch --ref <branch>
```

**Sources.** `released` installs a published release through the public
installer. `branch` builds a release from the dispatched ref on each platform
— through `build-release.yml`, the same workflow `release.yml` builds with —
and installs it with its bundled installer. A branch build's version is the
next patch marked as a pre-release of the commit (`1.60.4-branch.g3be7b8b`),
so `upgrade` from the latest release is a real version change. This proves an
app or installer change before it is tagged. `in-app-update` runs only for
`released`: it updates to GitHub's latest release.

**On a real machine:** the scenarios are plain scripts against the real
installed paths. From a checkout, on a machine with no Media Centaur install:

```sh
export MC_TAG=v1.60.3 MC_FROM_TAG=v1.60.2
s=install-repro/scenarios
platform=$([ "$(uname -s)" = Darwin ] && echo macos || echo linux)
for scenario in sudo-refused fresh-install reinstall "$platform/disabled-service" manual-start uninstall upgrade fresh-install-log; do
    "$s/$scenario" || break
done
```

`sudo-refused` needs passwordless `sudo` (`sudo -n`); skip it otherwise.
