# Auto-update + configurable update-check frequency

**Date:** 2026-06-07
**Status:** Approved, implementing

## Problem

Today the app polls the GitHub Releases API on a fixed 6-hour Oban cron, plus a
30s boot check and an on-mount check in Settings. When a new version is found
the user must click **Update now** to apply it. Two gaps:

1. No way to tune how often we poll GitHub. This matters because the check hits
   the **unauthenticated** GitHub API (~60 requests/hour per network IP), so a
   user who wants quicker detection — or none at all — has no lever.
2. No way to let the app install updates on its own.

## Settings (runtime-settable `MediaCentaur.Config` keys)

| Key | Default | Meaning |
|---|---|---|
| `update_check_enabled` | `true` | Whether background polling runs at all. Off = "manual only": GitHub is only contacted when the user clicks *Check for updates*. |
| `update_check_interval_minutes` | `360` | Minimum minutes between background checks. **Floor 15** (clamped on write). |
| `auto_update_enabled` | `false` | When a newer version is detected, download + install automatically. |

Defaults reproduce today's behavior exactly: poll every 6h, apply manually.

All three live in `defaults/media-centaur.toml` with explanatory comments and in
`@runtime_settable_keys`. Getters return the typed default when unset; the
interval getter clamps to the 15-minute floor so a bad stored value can't
out-poll the rate limit.

## Mechanism 1 — runtime-tunable frequency via an elapsed-time gate

Oban's cron schedule is fixed at boot and can't be reconfigured at runtime
cleanly. Rather than dynamic cron surgery or a self-rescheduling job (which
fights the 1-hour uniqueness window), the cron tick becomes the **floor**
(`*/15 * * * *`) and `CheckerJob.perform` gates each tick:

```
due_for_check?(force?) =
  force? or
  (update_check_enabled and now - last_check_at >= interval_minutes)
```

- A scheduled tick that isn't due yet returns `:ok` without touching the
  network — cheap timestamp comparison, no GitHub call.
- Manual *Check for updates* enqueues with `args: %{"force" => true}`, bypassing
  the gate so an explicit click always checks.
- `update_check_enabled == false` means scheduled ticks never check —
  "manual only" is honest.

The same `update_check_enabled` flag gates the **30s boot check** and the
**Settings on-mount auto-check**, so manual-only suppresses *every* background
contact, not just the cron. With polling off, the Settings card shows the
last-known status and "Last checked N ago" with the manual button.

Frequency thus becomes a pure `Config` read — no Oban reconfiguration. Effective
interval is quantized to the 15-minute tick, which is fine given the floor.

## Mechanism 2 — auto-apply with playback deferral

A new single-responsibility GenServer `MediaCentaur.SelfUpdate.AutoApply`
subscribes to `self_update:status` and `playback:events`:

- On `{:check_complete, {:update_available, _release}}` **and**
  `auto_update_enabled`:
  - nothing playing (`Sessions.any_active?/0` → `SessionRegistry.list() == []`):
    call `SelfUpdate.apply_pending()`.
  - something playing: set an internal `deferred?` flag, don't apply.
- On `{:playback_state_changed, %{state: :stopped}}`: if `deferred?`, the update
  is still pending, `auto_update_enabled`, and the screen is now idle → apply,
  clear the flag.

Because auto-apply only ever fires into an idle screen, a restart can never
interrupt an active viewer — that's why deferral (not immediate apply) is the
right model for a media center. The GenServer runs in all environments but
no-ops unless `SelfUpdate.enabled?()` (prod) and `auto_update_enabled`.

New helper: `MediaCentaur.Playback.Sessions.any_active?/0` (no existing function
answers "is *anything* playing" — only the per-entity `playing?/1`).

## Mechanism 3 — Settings UI written to be self-evaluable

System → Updates gains two labeled blocks. Each help string states *what* the
control does, *why* it matters, and *how to choose*:

**Checking for updates**
- Toggle "Automatically check for updates" (default on) + a minutes input shown
  when on. "Last checked N ago" line.
- Help: *"Media Centaur asks the GitHub Releases API whether a newer version
  exists. GitHub allows about 60 unauthenticated requests per hour from your
  network, so checking more often than every 15 minutes risks temporary
  rate-limiting with no benefit — releases are infrequent. Turn this off to
  check only when you click Check for updates."*

**Installing updates**
- Toggle "Install updates automatically" (default off).
- Help: *"When a new version is found, download and install it without asking.
  The app restarts to finish. If something is playing, the update waits until
  playback ends, so your session is never interrupted. Leave this off to review
  the release and click Update now yourself."*

Events call `Config.update/2`; the interval input is parsed and clamped.

## Testing (test-first)

- Config get/update for the three keys; interval floor clamping on write.
- `due_for_check?`: not-due scheduled tick skips; due tick checks; manual-only
  skips scheduled but `force` runs; first-ever check (no `last_check_at`) runs.
- `AutoApply` matrix with `Updater.apply_pending` and the session lookup stubbed:
  detected+enabled+idle → applies; +playing → defers (no apply); playback
  stop while deferred+idle → applies; detected+disabled → no-op; stop with
  nothing deferred → no-op.
- Settings render: both toggles, the minutes input, and help copy present.

## Out of scope

- Authenticated GitHub requests / higher rate limits (release signing is already
  tracked separately).
- Scheduling auto-apply to a maintenance window beyond "wait for idle".
