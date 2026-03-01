# Test Environment Filesystem Isolation

## Problem Statement

`Config.load!/0` reads the user's real `~/.config/media-centaur/backend.toml` during test runs. `config/runtime.exs` sets real watch directories for all environments without a test guard. Together, these cause `Admin.clear_database()` (called from `admin_test.exs:17`) to iterate the user's real watch dirs and `File.rm_rf!` every file in the real image cache. The `cleanup_stale_staging/0` function in `application.ex` also reaches into real production directories at test startup.

### Root cause chain

1. `runtime.exs` sets `watch_dirs: ["/mnt/videos/Videos"]` for all envs (no test guard)
2. `Config.load!/0` reads `~/.config/media-centaur/backend.toml` (the real user config)
3. Real watch dirs land in `:persistent_term` via Config
4. `application.ex:71-77` runs `cleanup_stale_staging/0` against real dirs at boot
5. `admin_test.exs:17` calls `Admin.clear_database()` which calls `clear_directory(Config.images_dir_for(dir))` on every real watch dir — deleting the user's image cache

## User-Facing Behavior

Running `mix test` becomes completely safe. No test run will ever read user configuration or touch any directory outside the repo, `System.tmp_dir!()`, or `priv/repo/` (test database). Existing behavior is otherwise unchanged.

## Design

### Data Model Changes

None.

### Approach

Three structural changes that make it impossible for any test — present or future — to touch real user directories:

**1. Guard `config/runtime.exs`**

Wrap the `watch_dirs` and `tmdb_api_key` settings so they don't apply in test:

```elixir
if config_env() != :test do
  watch_dirs = [System.get_env("MEDIA_DIR", "/mnt/videos/Videos")]
  config :media_centaur,
    watch_dirs: watch_dirs,
    tmdb_api_key: System.get_env("TMDB_API_KEY", ""),
    auto_approve_threshold: 0.85
end
```

**2. Add `:skip_user_config` flag to `config/test.exs`**

```elixir
config :media_centaur, :skip_user_config, true
config :media_centaur, :watch_dirs, []
```

**3. Modify `Config.load!/0` to respect the flag**

In `load_config/0`, check `Application.get_env(:media_centaur, :skip_user_config, false)`. When true, skip reading the TOML file entirely and use only app env defaults. This means:

- `:watch_dirs` is `[]` (from test.exs)
- `:watch_dir_images` is `%{}` (computed from empty watch_dirs)
- No real user paths enter `:persistent_term`

**Why this is defense-in-depth:**

| Layer | What it prevents |
|-------|-----------------|
| runtime.exs guard | Real watch dirs entering app env |
| `:skip_user_config` | User TOML overriding app env |
| `:watch_dirs, []` in test.exs | Any code iterating watch dirs touching real dirs |

Even if one layer is removed or misconfigured, the other two prevent real directory access.

### Tests that need filesystem paths

Pipeline, ingress, serializer, download_images, and watcher/supervisor tests already create temp dirs via `System.tmp_dir!()` and override `:persistent_term` directly. This pattern is correct and requires no changes.

The admin test does NOT override persistent_term — but with `:watch_dirs` set to `[]`, `Admin.clear_database()` iterates over nothing and performs zero filesystem operations. No change needed.

### Integration Points

None — purely internal. No cross-component contracts affected.

### Constraints

- Must not affect dev or prod config resolution (ADR-006: TOML at XDG paths)
- Config.load!/0 remains the single entry point for config (ADR-006)
- No raw SQL or Repo bypass (ADR-003)

## Acceptance Criteria

- [ ] `mix test` never reads `~/.config/media-centaur/backend.toml`
- [ ] `mix test` never touches any directory outside: the repo, `System.tmp_dir!()`, `priv/repo/`
- [ ] `Admin.clear_database()` in tests performs zero filesystem operations
- [ ] `cleanup_stale_staging()` at test startup is a no-op (empty watch_dirs)
- [ ] All existing tests pass with zero warnings
- [ ] Future tests that forget to override Config are safe by default (watch_dirs is `[]`)

## Decisions

See `adrs/2026-03-01-016-test-env-filesystem-isolation.md`.

## Smoke Tests

**Affected contracts:** None — no channel messages, no specs, no cross-component APIs changed.

**Tests to verify:**
- Run full `mix test` suite — all tests pass, zero warnings
- Confirm no filesystem access outside safe paths (verify by temporarily setting watch_dirs to a nonexistent path and observing no errors)
- Run `mix precommit` — clean pass
