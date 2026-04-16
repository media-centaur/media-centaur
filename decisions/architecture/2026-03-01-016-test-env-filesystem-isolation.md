---
status: proposed
date: 2026-03-01
---
# Test environment must never read user config or use real filesystem paths

## Context and Problem Statement

Running `mix test` reads the user's real TOML config (`~/.config/media-centarr/backend.toml`) and inherits real watch directories from `config/runtime.exs`. This causes destructive operations in tests — specifically `Admin.clear_database/0` — to `File.rm_rf!` the user's actual image cache. The test environment must be structurally isolated from all real user configuration and filesystem paths.

## Decision Outcome

Chosen option: "Defense-in-depth isolation via config guards, TOML skip flag, and empty watch_dirs", because it makes accidental real-directory access impossible at three independent layers rather than relying on each test to correctly override Config.

The three layers:
1. `config/runtime.exs` guards real watch_dirs behind `config_env() != :test`
2. `config/test.exs` sets `:skip_user_config, true` — `Config.load!/0` skips TOML reading entirely
3. `config/test.exs` sets `:watch_dirs, []` — any code iterating watch dirs is a no-op

Tests that need filesystem paths create temp dirs via `System.tmp_dir!()` and override `:persistent_term` directly, as pipeline/ingress/serializer tests already do.

### Consequences

* Good, because no test can ever touch real user directories, even if the test author forgets to override Config
* Good, because existing tests that already use temp dirs require no changes
* Good, because the fix is structural (compile-time config) rather than behavioral (per-test discipline)
* Bad, because `Config.load!/0` gains a branch for the skip flag — minor added complexity
