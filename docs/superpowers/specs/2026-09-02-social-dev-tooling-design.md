# Social dev tooling — design

**Date:** 2026-09-02
**Status:** approved
**Campaign:** `campaigns/friends-recommendations.md`

## Glossary

- **Dev relay** — the `social-relay` container run on this machine for development, on loopback port 2173.
- **Dev friend** — a second Nostr identity, held in a gitignored file, that the developer drives from the command line to act as another Media Centaur user.
- **Dev app** — the `media-centaur-dev` service on port 2160, which uses the developer's real database.
- **Allowlist** — the relay's `members` list of npubs. The dev relay's allowlist is the dev app's npub plus the dev friend's npub.

## Problem

Developing Social features needs a relay to talk to and someone on the other end. Today there is neither outside ExUnit: `FakeRelay` is test-only, and the one end-to-end check against the real relay used a throwaway client. Every feature session would rebuild that setup by hand.

## Decisions

1. **Entry point is `just`.** Recipes in the existing `justfile`, not a new script. Bare `just` currently runs the first recipe, `deploy`, which installs over the local production install; a `default` recipe that prints `just --list` goes first so bare `just` is safe and is the discovery entry point.
2. **The other user is a scripted friend**, not a second app instance. A second-instance override TOML is deferred until a feature needs two real UIs.
3. **Snapshot from the command line, no network.** The friend's recommendation carries a title snapshot built from flags. Only TMDB id, media type and name are required by the app; poster path, year and overview are optional flags. No TMDB lookup.
4. **Relay image built from the sibling repo** (`../social-relay`), so relay changes are testable here before a release. A `SOCIAL_RELAY_IMAGE` variable substitutes a published image.
5. **The dev app's npub is pasted once.** The app's secret is encrypted at rest, so no script can derive it; it is copied from **Discovery → Social → Your identity** and remembered in `priv/dev-social/members`.
6. **No arguments means help, never an error trace.** Every recipe and every mix subcommand prints its usage with a working example when called without what it needs.

## Pieces

### `justfile` recipes

| Recipe | Does |
|---|---|
| `default` | `just --list`. First recipe, so bare `just` lists instead of deploying. |
| `social` | Prints the walkthrough: the steps below with copy-pasteable commands. |
| `social-up [npub]` | Builds the relay image, `mix social.dev relay-config <npub>`, then runs the container (replacing a running one). Without an npub, reuses the remembered one or prints usage. |
| `social-down` | Stops and removes the container. |
| `social-reset` | `social-down` plus removes the data volume and `priv/dev-social/`. |
| `social-status` | Container state plus the NIP-11 document from `http://127.0.0.1:2173`. |
| `social-recommend *args` | `mix social.dev recommend {{args}}`. |
| `social-feed` | `mix social.dev feed`. |

Each recipe carries a doc comment, which is what `just --list` shows.

Container: name `social-relay-dev`, image tag `social-relay:dev`, port `127.0.0.1:2173` to the container's 2170, config bind-mounted read-only from `priv/dev-social/relay.toml`, bbolt file on the named volume `social-relay-dev-data`.

### `mix social.dev`

`lib/mix/tasks/social.dev.ex`, `use Boundary, top_level?: true, check: [in: false, out: false]` like the other tasks. It runs `Mix.Task.run("app.config")` and starts `:bitcoinex`, `:mint_web_socket` and `:jason`, never `app.start`: the task must not open the real database or bind port 2160.

| Subcommand | Does |
|---|---|
| (none) or `help` | Usage for every subcommand with an example. |
| `relay-config <npub>` | Creates `priv/dev-social/friend.nsec` if absent, writes `priv/dev-social/members`, writes `priv/dev-social/relay.toml` with `service_url = "ws://127.0.0.1:2173"`, `listen = "0.0.0.0:2170"`, `database = "/data/events.db"`, and both npubs. Prints the friend's npub and the relay URL to paste into the app. |
| `npub` | Prints the friend's npub. |
| `recommend <movie\|series> <tmdb_id> --name NAME [--year YYYY] [--poster-path PATH] [--overview TEXT] [--note TEXT]` | Builds a `TMDB.Title`, signs a kind 32160 event as the friend through `Recommendations.Translation.to_event/3`, connects with `Nostr.Connection`, answers the AUTH challenge, publishes, and exits 0 on `OK true` or 1 with the relay's reason. Timeout 5 s. |
| `feed` | Connects the same way, requests every kind 32160 the relay holds, prints one line per event: author (`You`, `Friend`, or short npub), address, name, note, relative time. |

Media type on the command line is `movie` or `series`; `series` maps to `:tv_series`.

Relay URL defaults to `ws://127.0.0.1:2173` and is overridable with `--relay`.

### Files

`priv/dev-social/` is gitignored: `friend.nsec`, `members`, `relay.toml`.

## Walkthrough (`just social` prints this)

```
1. just social-up npub1...        # your npub: Discovery → Social → Your identity → Copy
2. In the dev app, Discovery → Social: add relay ws://127.0.0.1:2173,
   add a friend with the npub printed by step 1.
3. just social-recommend movie 603 --name "Sample Movie" --note "try it"
4. just social-feed                # what the relay holds, including what you sent
```

## Testing

`test/mix/tasks/social_dev_test.exs` against `FakeRelay.start(auth: true)`:

- `recommend` publishes an event that the fake relay receives, that `Nostr.Event.verify/1` accepts, and that `Translation.from_event/1` turns into a recommendation with the given title and note; the task exits 0.
- `recommend` against a relay answering `OK false` exits 1 and prints the reason.
- `feed` prints one line per stored event.
- `relay-config` writes a TOML whose `members` are exactly the two npubs, and a second run keeps the same friend key.

The task takes the state directory from an option so tests use `tmp_dir`. The justfile and Docker are not unit-tested.

## Docs

- `docs/social.md`: a **Development** section pointing at `just social`.
- `campaigns/friends-recommendations.md`: decision and status entries.

## Deferred

A second friend identity, a second app instance, relay outage simulation, and moving the dev relay to a published image by default.
