# Media Centaur dev convenience recipes — run `just --list` to see them.
#
# `just deploy` builds the current working tree as a production release and
# installs it over your LOCAL prod install (~/.local/lib/media-centaur):
# schema + data migrations, atomic `current` symlink flip, and a service
# restart. This is the SAME path the in-app updater runs — it re-execs the
# bundled `media-centaur-install` in default mode — just sourced from this
# build instead of a downloaded GitHub release.
#
# Dev convenience only. Shipping is still `/ship` → tag → release; this is
# not a public install path and does not replace it. Note `deploy` touches
# real state: it migrates your production DB and briefly stops the service.

_release := "_build/prod/rel/media_centaur"

# Build the working tree and install it as your local production install.
deploy:
    scripts/preflight
    @just _install

# Like `deploy`, but wipes _build/prod first for a clean from-scratch build.
deploy-clean:
    scripts/preflight --clean
    @just _install

# Stop the service (ignored if not running), then run the freshly built
# installer in default mode: it re-runs migrations against the new release,
# flips `current`, and restarts the (enabled) service.
#
# The stop is required because between releases the version in mix.exs is
# unchanged, so the installer reinstalls the SAME releases/<version>/ dir —
# stopping first avoids deleting files out from under the running BEAM.
_install:
    -systemctl --user stop media-centaur
    {{_release}}/bin/media-centaur-install
