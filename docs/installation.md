# Installation

Media Centarr ships as a self-contained Linux release. Erlang/Elixir
are bundled — you do not need to install them.

**Supported platform:** Linux x86_64 with glibc.
musl (Alpine), aarch64, macOS, and Windows are not supported by the
official build. To run on those, build from source — see the README.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/media-centarr/media-centarr/main/installer/install.sh | sh
```

The bootstrap script:

1. Verifies you're on Linux x86_64 (glibc).
2. Resolves the latest GitHub Release.
3. Downloads the release tarball and `SHA256SUMS`.
4. Verifies the checksum.
5. Hands off to the installer bundled inside the tarball.

The bundled installer then:

1. Stages the release at
   `~/.local/lib/media-centarr/releases/<version>/`.
2. Seeds `~/.config/media-centarr/media-centarr.toml` (only on first
   install — never overwrites your edits).
3. Generates `~/.config/media-centarr/secrets.env` with a random
   `SECRET_KEY_BASE` (only on first install — `chmod 0600`).
4. Installs the systemd user unit at
   `~/.config/systemd/user/media-centarr.service`.
5. Runs database migrations against the new release.
6. Atomically flips `~/.local/lib/media-centarr/current` to point at
   the new version.
7. Restarts the service if it was already running.

If migrations fail at step 5, the symlink does NOT flip. The previous
install (if any) keeps serving — the new release directory is left
behind for inspection.

After a first-time install, enable and start the service:

```sh
systemctl --user enable --now media-centarr.service
```

The service listens on `http://127.0.0.1:4000`.

## Update

From inside an installed environment:

```sh
~/.local/lib/media-centarr/current/bin/media-centarr-install --update
```

This resolves the latest release tag, downloads it, verifies the
checksum, and runs the same atomic install flow as a fresh install.

There is no auto-update — you control when updates happen.

To install a specific version instead of latest, re-run the bootstrap
with `--version`:

```sh
curl -fsSL https://raw.githubusercontent.com/media-centarr/media-centarr/main/installer/install.sh | sh -s -- --version v0.3.0
```

## Configure

- `~/.config/media-centarr/media-centarr.toml` — application settings.
  See the comments in the file for available keys.
- `~/.config/media-centarr/secrets.env` — runtime environment
  variables (loaded by the systemd unit and the installer).
  - `SECRET_KEY_BASE` — generated automatically; do not change.
  - `TMDB_API_KEY` — optional, for metadata enrichment.
  - `MEDIA_DIR` — optional, root directory to scan for media.

After editing either file, restart:

```sh
systemctl --user restart media-centarr.service
```

## Uninstall

```sh
~/.local/lib/media-centarr/current/bin/media-centarr-install --uninstall
```

This stops + disables the systemd unit, removes the install
directory, and removes the unit file.

**Config and data are preserved**:

- `~/.config/media-centarr/`
- `~/.local/share/media-centaur/` (database, downloaded images)

Delete those by hand if you want a full wipe.

## Layout reference

```
~/.local/lib/media-centarr/
    releases/
        0.3.0/
            bin/media_centarr
            bin/media-centarr-install
            share/systemd/media-centarr.service
            share/defaults/media-centarr.toml
            erts-15.x/, lib/, releases/
        0.4.0/
            ...
    current -> releases/0.4.0
~/.config/media-centarr/
    media-centarr.toml
    secrets.env
~/.config/systemd/user/
    media-centarr.service        (pinned to current/, never edited per-version)
~/.local/share/media-centaur/
    database, image cache, persistent state
```

The systemd unit references `current/bin/media_centarr`, so version
flips never require editing the unit. Old release directories under
`releases/` are kept until you remove them by hand — useful for
rolling back by changing the symlink:

```sh
ln -sfn releases/0.3.0 ~/.local/lib/media-centarr/current.new
mv -Tf ~/.local/lib/media-centarr/current.new ~/.local/lib/media-centarr/current
systemctl --user restart media-centarr.service
```

## Building from source

If you're a developer or need to run on an unsupported platform:

```sh
mix setup           # install deps, create DB, run migrations
mix phx.server      # dev server on http://localhost:4001
./scripts/release   # build a production release in _build/prod/rel/
./scripts/install   # install the just-built release (legacy script,
                    # preserved for source-build workflows)
```
