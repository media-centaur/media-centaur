---
status: accepted
date: 2026-02-20
---
# TOML configuration at XDG paths and Req as HTTP client

## Context and Problem Statement

The application needs user-editable configuration (watch directories, TMDB API key, image paths) and a reliable HTTP client for TMDB API calls and image downloads. These are two narrow technology choices made at the same time.

## Decision Outcome

**Configuration:** Chosen option: "TOML files at XDG paths with `defaults/` fallback", because TOML is human-readable, has a well-defined spec, and supports comments — ideal for a config file users may hand-edit. The `defaults/media-manager.toml` file ships with the repo containing every configurable key and its default value. At runtime, `MediaManager.Config` (a GenServer) reads user config from XDG paths and falls back to defaults.

**HTTP client:** Chosen option: "Req", because it is the modern Elixir HTTP client with built-in support for `Req.Test` (pluggable test stubs without mocking libraries), automatic JSON encoding/decoding, and retry middleware. Never use `:httpoison`, `:tesla`, or `:httpc`.

### Consequences

* Good, because `defaults/media-manager.toml` documents every configurable option in one place
* Good, because TOML comments explain what each key controls — the config file is self-documenting
* Good, because `Req.Test` enables per-test HTTP stubs without a mocking library — used extensively in pipeline tests
* Bad, because TOML has limited expressiveness for complex nested structures (acceptable — our config is flat)
