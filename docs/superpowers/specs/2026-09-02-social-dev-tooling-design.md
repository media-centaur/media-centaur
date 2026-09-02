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
5. **The dev app's npub is pasted once.** The app's secret is encrypted at rest, so no script can derive it; it is copied from **Discovery → Social → Your identity** and remembered by the relay's dev script in its own config.
6. **No arguments means help, never an error trace.** Every recipe and every mix subcommand prints its usage with a working example when called without what it needs.
7. **Each repo owns its half** (unify_design, below). The relay repo owns "run me in dev with these members": `scripts/dev-relay` there builds the image, writes the TOML and runs the container. The app repo owns "act as a friend": `mix social.dev`. The app's justfile is the single front door and delegates.

## unify_design adjudication

**Core idea.** The dev friend is a second instance of the Nostr client the app already has, driven from a shell instead of a LiveView. Everything it does is connect, authenticate, publish or query, and translate, and the app owns every one of those pieces.

**Greenfield shape.** Two owners. The relay knows how to run itself with a member list; the app knows how to be a Nostr participant. A synchronous single-purpose session over `Nostr.Connection` is the one piece neither has.

**Diff against the code, and each disposition.**

| Gap | Kind | Disposition |
|---|---|---|
| Keys, signing, translation, connection | clean seams | Used as they are: `Nostr.Keys`, `Nostr.Event`, `Recommendations.Translation`, `Nostr.Connection`. |
| The app writing the relay's TOML | duplicated schema | Moved to the relay repo (`scripts/dev-relay`). The app never spells the relay's config keys. |
| A "You" label in `feed` needing the app's npub in the app's dev dir | second source of truth | Dropped. `feed` prints `friend` for the friend's own events and a shortened npub for anyone else. |
| `series` on the command line mapped to `tv_series` | second vocabulary | Dropped. The command line takes `movie` or `tv_series`, the words the event address already uses. |
| Connect, auth, do one thing, disconnect | missing piece | `Nostr.OneShot` in the `Nostr` context: `publish/3` and `query/3`, synchronous, over one short-lived `Connection`. Protocol only, no domain meaning, so it belongs there. |

**Cost.** One small script in the relay repo and one cross-repo path (`../social-relay`) that the justfile already assumed for the image build. No app-side config writing at all, so the app side shrinks.

## Pieces

### `justfile` recipes

| Recipe | Does |
|---|---|
| `default` | `just --list`. First recipe, so bare `just` lists instead of deploying. |
| `social` | Prints the walkthrough: the steps below with copy-pasteable commands. |
| `social-up [npub]` | `mix social.dev npub` for the friend's key, then `../social-relay/scripts/dev-relay up <npub> <friend-npub>`. Without an npub, `dev-relay up` reuses its existing config; if there is none, prints usage. |
| `social-down` | Stops and removes the container. |
| `social-reset` | `dev-relay reset` (container, volume and config) plus removes `priv/dev-social/`, so the friend gets a new key and must be re-added in the app. |
| `social-status` | `dev-relay status`: container state plus the NIP-11 document from `http://127.0.0.1:2173`. |
| `social-recommend *args` | `mix social.dev recommend {{args}}`. |
| `social-feed` | `mix social.dev feed`. |

Each recipe carries a doc comment, which is what `just --list` shows.

### `scripts/dev-relay` (relay repo)

`up <npub>...` builds `social-relay:dev` from the working tree (skipped when `SOCIAL_RELAY_IMAGE` is set), writes `dev/relay.toml` (gitignored) with `listen = "0.0.0.0:2170"`, `database = "/data/events.db"`, `service_url = "ws://127.0.0.1:2173"` and the given members, replaces any running `social-relay-dev` container (port `127.0.0.1:2173` to 2170, config bind-mounted read-only, bbolt file on the named volume `social-relay-dev-data`), waits for the NIP-11 document, and prints the URL. `up` with no npubs reuses `dev/relay.toml`. `down` removes the container. `reset` also removes the volume and `dev/`. `status` prints the container state and the NIP-11 document. No arguments prints usage.

### `mix social.dev`

`lib/mix/tasks/social.dev.ex`, `use Boundary, top_level?: true, check: [in: false, out: false]` like the other tasks. It runs `Mix.Task.run("app.config")` and starts `:bitcoinex`, `:mint_web_socket` and `:jason`, never `app.start`: the task must not open the real database or bind port 2160.

| Subcommand | Does |
|---|---|
| (none) or `help` | Usage for every subcommand with an example. |
| `npub` | Creates `priv/dev-social/friend.nsec` if absent and prints the friend's npub, nothing else, so a recipe can capture it. |
| `recommend <movie\|tv_series> <tmdb_id> --name NAME [--year YYYY] [--poster-path PATH] [--overview TEXT] [--note TEXT]` | Builds a `TMDB.Title`, signs a kind 32160 event as the friend through `Recommendations.Translation.to_event/3`, publishes it with `Nostr.OneShot.publish/3`, and exits 0 on `OK true` or fails with the relay's reason. |
| `feed` | `Nostr.OneShot.query/3` for every kind 32160 the relay holds; prints one line per event: author (`friend` or a shortened npub), address, name, note, relative time. |

Relay URL defaults to `ws://127.0.0.1:2173`, overridable with `--relay`. The state directory defaults to `priv/dev-social`, overridable with `--dir` (tests use it).

### `Nostr.OneShot`

Synchronous, single-purpose relay sessions for callers that are not long-lived processes. `publish(url, event, signer)` and `query(url, filters, signer)` start one `Connection`, wait for `:connected`, open a subscription (`ids: [event id]` for a publish, the given filters for a query), and treat its `:eose` as proof that any `AUTH` challenge has been answered, because `Connection` re-issues subscriptions only after a successful `AUTH`. A publish then sends the event and returns the relay's `OK` verdict; a query returns the events received before `:eose`. `{:auth, {:failed, _}}`, a `:closed` whose reason is not `auth-required:`, `{:disconnected, _}` and the 5 s timeout all return `{:error, reason}`. The connection is stopped on every path.

### Files

`priv/dev-social/` is gitignored and holds `friend.nsec`.

## Walkthrough (`just social` prints this)

```
1. just social-up npub1...        # your npub: Discovery → Social → Your identity → Copy
2. In the dev app, Discovery → Social: add relay ws://127.0.0.1:2173,
   add a friend with the npub printed by step 1.
3. just social-recommend movie 603 --name "Sample Movie" --note "try it"
4. just social-feed                # what the relay holds, including what you sent
```

## Testing

`test/media_centaur/nostr/one_shot_test.exs` against `FakeRelay`: publish round-trips with and without `auth: true`; a refused publish returns the relay's reason; query returns the stored events; an unreachable relay returns `{:error, {:disconnected, _}}`.

`test/mix/tasks/social_dev_test.exs` against `FakeRelay.start(auth: true)` with `--dir` pointing at `tmp_dir`:

- `recommend` publishes an event the fake relay receives, that `Nostr.Event.verify/1` accepts, and that `Translation.from_event/1` turns into a recommendation with the given title and note.
- `recommend` against a relay answering `OK false` raises `Mix.Error` carrying the reason.
- `feed` prints one line per stored event.
- `npub` prints the same npub on a second run, and prints only the npub.
- no arguments, or a subcommand missing its arguments, prints usage.

The justfile, `scripts/dev-relay` and Docker are not unit-tested.

## Docs

- `docs/social.md`: a **Development** section pointing at `just social`.
- `campaigns/friends-recommendations.md`: decision and status entries.
- Relay repo: `CLAUDE.md` or `docs/operating.md` mention of `scripts/dev-relay`, and its campaign file.

## Deferred

A second friend identity, a second app instance, relay outage simulation, and moving the dev relay to a published image by default.
