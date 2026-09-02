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

set positional-arguments

_release := "_build/prod/rel/media_centaur"
_dev_relay := "../social-relay/scripts/dev-relay"

# List the recipes (bare `just` lands here, never on deploy).
default:
    @just --list

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

# --- Social: a dev relay plus a scripted friend ------------------------------

# How to develop Social features: the setup walkthrough.
social:
    @echo 'Social development: a private relay in Docker plus a scripted "friend".'
    @echo
    @echo '1. just social-up npub1...     your npub: Discovery → Social → Your identity → Copy'
    @echo '                               builds ../social-relay, starts it on ws://127.0.0.1:2173,'
    @echo '                               and prints the friend'"'"'s npub'
    @echo '2. In the dev app (Discovery → Social): add relay ws://127.0.0.1:2173,'
    @echo '   then add a friend with the npub from step 1.'
    @echo '3. just social-recommend movie 603 --name "Sample Movie" --note "try it"'
    @echo '                               the friend recommends a title; it appears in your Feed'
    @echo '4. just social-feed            everything the relay holds, including what you sent'
    @echo
    @echo 'Also: just social-status · just social-down · just social-reset (new friend key)'
    @echo '      mix social.dev            all friend options (--year, --poster-path, --relay, ...)'

# Start (or restart) the dev relay with you and the friend as members.
social-up npub="":
    #!/usr/bin/env bash
    set -euo pipefail
    mix compile >/dev/null
    friend=$(mix social.dev npub | tail -n1)
    if [ -n "{{npub}}" ]; then
        {{_dev_relay}} up "{{npub}}" "$friend"
    elif [ -f ../social-relay/dev/relay.toml ]; then
        {{_dev_relay}} up
    else
        echo 'First run needs your npub (Discovery → Social → Your identity → Copy):'
        echo '  just social-up npub1...'
        exit 2
    fi
    echo
    echo "friend's npub (add it under Discovery → Social → Friends): $friend"

# Stop the dev relay.
social-down:
    {{_dev_relay}} down

# Stop the dev relay, drop its data, and forget the friend's key.
social-reset:
    {{_dev_relay}} reset
    rm -rf priv/dev-social
    @echo "friend key removed; the next social-up prints a new npub to add in the app"

# Container state, members, and the relay's NIP-11 document.
social-status:
    {{_dev_relay}} status

# The friend recommends a title: social-recommend movie 603 --name "Sample Movie" [--note "..."]
social-recommend *args:
    mix social.dev recommend "$@"

# Everything the dev relay holds, newest first.
social-feed:
    mix social.dev feed
