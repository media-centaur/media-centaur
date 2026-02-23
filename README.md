# Freedia Center — Media Manager

Phoenix/Elixir application that manages the Freedia Center media library. Watches configured directories for video files, scrapes metadata and artwork from TMDB, and serves the library to the [user-interface](../user-interface) over Phoenix Channels (WebSocket).

## Quick Start

```bash
mix setup          # install deps, create DB, run migrations, build assets
mix phx.server     # start dev server at http://localhost:4000
mix test           # run tests
mix precommit      # compile --warnings-as-errors, format, test
```

## Documentation

- [`CLAUDE.md`](CLAUDE.md) — project conventions, architecture principles, testing strategy
- [`PIPELINE.md`](PIPELINE.md) — Broadway pipeline architecture
- [`../specifications/`](../specifications/) — cross-component contracts (API, data format, playback, images)
