---
status: accepted
date: 2026-03-01
---
# Test environment must never read user config or use real filesystem paths

## Context and Problem Statement

`mix test` once read the user's real TOML config and inherited real media directories from `config/runtime.exs`, so a destructive operation under test (clearing the database) deleted the user's image cache. Isolation has to be structural, not a per-test discipline.

## Decision Outcome

Three independent layers, so no single forgotten override can reach a real directory:

1. `config/runtime.exs` loads real `media_dirs` only when `config_env() != :test`.
2. `config/test.exs` sets `:skip_user_config, true`, so config loading never reads the user's TOML under test.
3. `config/test.exs` sets `:media_dirs, []`, so any code iterating media directories is a no-op.

A test that needs a filesystem creates a temporary directory and overrides the relevant config itself; it never points at a configured path.

### Consequences

* A test that forgets to override config runs against an empty configuration rather than the user's machine.
* Filesystem-shaped tests carry explicit fixture setup; the `automated-testing` skill has the recipe.
