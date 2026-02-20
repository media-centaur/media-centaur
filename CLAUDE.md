Read `AGENTS.md` for Elixir, Phoenix, LiveView, Ecto, and CSS/JS guidelines.

# Freedia Center — Media Manager

A Phoenix/Elixir web application that manages the Freedia Center media library. It is the **write-side** of the system: it creates and edits entity records, scrapes metadata from external APIs, and downloads artwork images. The `user-interface` app consumes its output as a read-only consumer.

## Build & Run

```bash
mix setup              # install deps, create DB, run migrations, build assets
mix phx.server         # start dev server (http://localhost:4000)
mix test               # run tests (creates and migrates test DB automatically)
mix precommit          # compile --warning-as-errors, unlock unused deps, format, test
```

Run `mix precommit` before finishing any set of changes and fix all issues it reports.

## Repository Layout

| Path | Purpose |
|------|---------|
| `lib/media_manager/` | Business logic: scraping, JSON I/O, image downloading, entity management |
| `lib/media_manager_web/` | Phoenix web layer: router, LiveViews, controllers, components |
| `lib/media_manager_web/components/` | Shared HEEx components and layouts |
| `priv/repo/migrations/` | Ecto migrations |
| `priv/repo/seeds.exs` | Database seed data |
| `test/` | ExUnit tests |
| `assets/` | JS and CSS source (esbuild + Tailwind v4) |
| `defaults/` | Shipped starter config files (git-tracked seed values; never overwritten at runtime) |
| `AGENTS.md` | Elixir/Phoenix/LiveView/Ecto/CSS/JS coding rules |

## Architecture Principles

- **This app owns all writes.** Only the manager writes `media.json` and `data/images/`. The `user-interface` never writes these files.
- **Schema.org is the data model.** All entity fields and types come from schema.org vocabulary. Read `DATA-FORMAT.md` before writing any code that encodes or decodes entity JSON.
- **UUIDs are stable forever.** An entity's `@id` is assigned once and never changed. It doubles as the image directory name. Never reassign or reuse a UUID.
- **File system is the integration point.** There is no IPC with the user-interface. Write files to the data directory; the UI picks them up via hot-reload.
- **Images: one copy per role.** Store one high-quality image per role (`poster`, `backdrop`, `logo`, `thumb`). Never store multiple resolutions. See `IMAGE-CACHING.md`.
- **External API clients use `Req`.** Never use `:httpoison`, `:tesla`, or `:httpc`. `Req` is included and is the preferred HTTP client.

## Specifications

Cross-component specifications live in the **[freedia-center/specifications](https://github.com/freedia-center/specifications)** repository, stored locally at `../specifications` relative to this repo.

| Document | Contents |
|----------|---------|
| [`DATA-FORMAT.md`](../specifications/DATA-FORMAT.md) | JSON schema for `media.json` — entity types, field names, sub-types, examples |
| [`IMAGE-CACHING.md`](../specifications/IMAGE-CACHING.md) | Image roles, directory layout, remote URL patterns, manager/UI responsibilities |
| [`COMPONENTS.md`](../specifications/COMPONENTS.md) | How the manager and user-interface relate; the integration contract |

### Reading the Specs

- **Before writing any code that reads or writes `media.json`**, read `DATA-FORMAT.md` in full.
- **Before writing any image download or storage code**, read `IMAGE-CACHING.md` in full.
- **When adding a new entity field or type**, check [schema.org](https://schema.org) first. Use the canonical schema.org property name if one fits. Only introduce a non-schema.org field if there is no reasonable match, and document the reason in `DATA-FORMAT.md`.
- Field names (`name`, `datePublished`, `contentUrl`, `containsSeason`, etc.) and type names (`Movie`, `TVSeries`, `VideoGame`, `ImageObject`, `PropertyValue`) are schema.org identifiers — do not rename them.

### Working with the Specs

- Treat `DATA-FORMAT.md` as the authoritative contract for the JSON written by this app and read by the user-interface. When in doubt about a field name, type, or structure, the spec wins.
- `IMAGE-CACHING.md` specifies the exact `contentUrl` path format (`images/{uuid}/{role}.{ext}`), image roles, and remote URL patterns for each source (TMDB, Steam). Follow these precisely — the user-interface uses them verbatim.
- `COMPONENTS.md` describes the integration contract between manager and user-interface. Refer to it when designing new features that affect the shared data directory.

### Keeping the Specs Updated

When a format decision changes — a new field, a new entity type, a changed image role, a modified `config.json` structure — **update the spec first**, then update the implementation:

1. Edit the relevant file in `../specifications` (e.g. `DATA-FORMAT.md`).
2. Update this app's implementation to match.
3. Note in `COMPONENTS.md` or the relevant spec if the change affects the user-interface, so its `CLAUDE.md` can be updated too.

Never let the implementation drift ahead of the spec. The spec is how the user-interface team (and future agents) learn what to expect from files this app produces.

### Keep Documentation Updated

Any .md documentation created for this project should be kept up to date.

## Defaults

The `defaults/` directory contains git-tracked starter config files. These are seed values shipped with the repo — they represent every configurable option with a logical default. They are **never overwritten at runtime**; the running app reads user config from XDG paths and falls back to these.

| File | Purpose |
|------|---------|
| `defaults/media-manager.toml` | All TOML configuration keys with their default values |

> **Keep `defaults/media-manager.toml` complete.** Every configuration key recognised by `MediaManager.Config` must have an entry in `defaults/media-manager.toml` with a logical default value and a comment explaining what it controls. Add the entry whenever a new config key is introduced. The file must always be valid TOML and parse without errors.

## Plans

Implementation plans live in `plans/` and are prefixed with a unique incrementing
number (e.g. `001-animate-menu-bar.md`, `002-add-search.md`). The number ensures
ordering and prevents naming collisions. Each plan must be **self-contained** —
it must include all context required to execute fully in a new session, without
relying on the conversation history from the session where the planning was done.

Always write the plan and save it before asking to execute.
