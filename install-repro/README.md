# Install reproduction

Scripted install paths for Media Centaur, run against real environments so an
installer fault can be proven, fixed and kept fixed. A **scenario** is one
script that runs one install path and ends in pass or fail.

## macOS

Environment: a GitHub macOS runner (`macos-14`, Apple Silicon), through
[`.github/workflows/install-repro-macos.yml`](../.github/workflows/install-repro-macos.yml).

| Scenario | What it proves |
|---|---|
| `sudo-refused` | Both installers refuse `sudo` and write nothing. Needs a clean machine, so it runs first. |
| `fresh-install` | The public installer, run without `sudo`, ends with the LaunchAgent loaded and running and the app answering on port 2160. |
| `reinstall` | Running the installer over an existing install loads the agent again. |
| `disabled-label` | An install over a disabled `com.media-centaur.app` label still loads the agent. |
| `manual-start` | With the agent unloaded, `bin/media_centaur daemon` boots the app with `secrets.env` loaded; `service install` restores autostart. |
| `uninstall` | The app, plist and agent are gone, the label is disabled, and config and data are kept. |
| `upgrade` | Installing the tag over the release before switches `current` to it, and the running app reports the new version. |
| `fresh-install-log` | The fresh install logged no `[error]` line. |
| `in-app-update` | From the release before, the update the Settings button starts reaches the latest release and the agent ends on it. |

The first eight run in order in one job, each building on the state the one
before left. `in-app-update` runs in its own job on a clean runner. It always
updates to GitHub's latest release, so it tests the tag under test only when
that tag is the latest — run it without a tag to test the latest release. Each job uploads `collect-evidence` output (app logs,
update handoff logs, launchd state) as an artifact.

**When it runs:** by hand, when we decide to — nothing triggers it
automatically. To run it against a published tag (empty means the latest):

```sh
gh workflow run install-repro-macos.yml -f tag=v1.60.1
```

**On a real Mac:** the scenarios are plain scripts against the real installed
paths. From a checkout, on a Mac with no Media Centaur install:

```sh
export MC_TAG=v1.60.1
for s in sudo-refused fresh-install reinstall disabled-label manual-start uninstall; do
    install-repro/scenarios/macos/$s || break
done
```

`sudo-refused` needs passwordless `sudo` (`sudo -n`); skip it otherwise.
