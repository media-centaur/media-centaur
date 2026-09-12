---
status: planning
started: 2026-09-12
last_updated: 2026-09-12
---
# External processes must outlive the app that launched them

## Goal

mpv dies every time Media Centaur restarts, so every update costs the viewer
whatever they were watching. It should not: mpv's lifetime belongs to the
person watching, not to the app that started it. The machinery to reattach
after a restart already exists ([ADR-023](../decisions/architecture/2026-03-06-023-durable-process-design.md))
and has **never once run**, because mpv is spawned as a BEAM port and cannot
survive the VM. Fix the lifetime binding, and document the facts where the
next person touching mpv will meet them — prose alone is what failed here.

## Status

**Planning.** Diagnosed and measured 2026-09-11/12; design pass done
(`unify_design`). No code yet. One naming decision open.

## Why this is not "a regression"

Worth stating first, because it changes what the fix is. The working
assumption when this came up was that mpv had once been detached and was
later moved to a port. **It never was.**

* `Port.open({:spawn_executable, …})` is in the *first* playback commit —
  `11807e78`, 2026-02-22 12:24 ("feat: set up a playback genserver and basic
  pubsub channel / socket stuff"). `git log -S "Port.open" --follow` on
  `mpv_session.ex` returns only the two project renames.
* `git log -S setsid --all` shows the first detached spawn anywhere in the
  repo is `207cf4ab` — the Apps launcher, 2026-08-28, six months later.

So there is no earlier behaviour to restore. What happened instead:
[ADR-023](../decisions/architecture/2026-03-06-023-durable-process-design.md)
(2026-03-06) *described* MpvSession as

> MpvSession spawns an mpv process with a unique socket path. On restart, it
> generates a new socket path and **orphans the still-running mpv process — the
> user's playback continues** but the backend can no longer control it.

That was already false when written. A port child cannot outlive the VM. The
ADR then prescribed "stable socket path + reconnect", which shipped correctly
and solved a problem that could not occur. The claim was never tested, and the
code built on it has run zero times in production.

**The lesson to encode: an assertion that a process survives something is a
measurement, not an inference.** It was wrong in an ADR, and it is wrong again
today in `Apps.Launcher`'s moduledoc (below).

## Measurements

All taken 2026-09-11/12 on this machine, with transient `systemd-run --user`
units rather than by restarting the daily driver.

**Has recovery ever fired?** `journalctl --user -u media-centaur-dev --since
"30 days ago" | grep -c "recovery: found live session"` → **0**. No recovery
lines of any kind.

**What actually kills a detached child:**

| Unit config | `setsid -f` child after unit stop |
|---|---|
| `KillMode=mixed` (what `defaults/media-centaur-dev.service:46` ships) | **KILLED** |
| `KillMode=process` (what `defaults/media-centaur.service:24` ships) | **SURVIVED** |

So there are **two independent kill mechanisms** and both must be addressed:

1. **The port.** `mpv_session.ex:407` spawns mpv with
   `Port.open({:spawn_executable, …})`. When the VM halts, `erl_child_setup`
   SIGKILLs every port-spawned child; Erlang offers no detach for port
   programs. Kills mpv in dev *and* prod.
2. **The cgroup.** `KillMode=mixed` sends SIGTERM to the main process and then
   SIGKILL to everything left in the unit's cgroup. `setsid` escapes the port
   but **not** the cgroup — the detached child's cgroup is still
   `…/mc-killtest.service`. Dev-only, but dev is the daily driver.

## The second instance, live today

`MediaCentaur.Apps.Launcher`'s moduledoc says:

> `setsid -f` forks the command into its own session: the intermediate process
> exits immediately, the port closes, and **the launched app survives Media
> Centaur restarts**.

Per the table above, false under the dev unit. Steam and every other app
launched from `/apps` is being SIGKILLed on restart, with a confident comment
above it saying otherwise. Same defect, same class of unverified claim.

## Design (from the `unify_design` pass)

**Core idea:** a playback session is an external process the app *attaches to*,
not a child it *owns*. mpv's lifetime belongs to the viewer and their remote.
The app launches it, observes it over IPC, and reattaches after a restart. A
port **is** a lifetime binding, which is why it is the wrong mechanism.

This matters because the app is not mpv's controller here: the owner drives
playback from a universal remote bound to mpv's own key bindings, and uses
Media Centaur only to start it. A surviving mpv is not stranded.

**What the port actually buys, and why removing it costs nothing:**

| Port provides | Needed? |
|---|---|
| Process lifetime binding | This *is* the defect |
| `:stderr_to_stdout` | Redundant — `--log-file` already passed (`mpv_session.ex:~401`) |
| `{:exit_status, n}` for exit classification | Near-worthless; mpv is very stable and rarely crashes |

Critically, **control is the IPC socket, not the port.** Pause, seek, property
observation and progress tracking all run over `--input-ipc-server` and are
untouched by detaching. And `{:tcp_closed, _}` is *already* a first-class exit
signal (`mpv_session.ex:326`; see the comment at `:77` — "the first exit signal
(tcp_closed OR exit_status)"). The replacement path is already built.

**One detached-spawn mechanism, not two.** Detached spawning exists once today
(`Apps.Launcher`, broken in practice) and is needed a second time (mpv).
Promote it to a single platform-aware seam used by both. This collapses
duplication that exists now — not speculative abstraction.

### Dispositions

| # | Incoherence | Disposition |
|---|---|---|
| 1 | mpv spawned as a BEAM port | Fix — route through the shared seam |
| 2 | dev unit `KillMode=mixed` kills detached children | Fix — match prod's `process` |
| 3 | `Apps.Launcher` asserts survival it does not deliver | Fix — same defect, owner said explicitly to include it |
| 4 | ADR-023's MpvSession premise is false as written | **Amend, not supersede** — its principle (resumable *or* idempotent-restart) is sound; only the factual row is wrong |
| 5 | `exit_status` used for exit classification | Drop — degrade to "the socket went away" |
| 6 | `setsid` is absent on macOS | Settle by measurement — a plain double-fork (`sh -c 'cmd &'`) is portable and may suffice, since what matters is only that the *intermediate* process exits so the port closes |

## Decisions made

* `2026-09-11` — mpv stops on restart because it is a BEAM port child **and**
  because the dev unit's `KillMode=mixed` SIGKILLs the cgroup. Both measured;
  both must be fixed. Neither is a regression — see above.
* `2026-09-12` — Not a regression. `Port.open` dates from the first playback
  commit `11807e78` (2026-02-22); no detached mpv ever existed. ADR-023's
  premise was false when written.
* `2026-09-12` — Removing the port costs no capability. Control is IPC;
  `tcp_closed` is already handled as an exit signal; `--log-file` already
  covers diagnostics. Only the numeric exit status is lost, and mpv's
  stability makes that near-worthless.
* `2026-09-12` — **Owner: fix `Apps.Launcher` in the same pass.** "yes,
  DEFINITELY fix it" — the scope explicitly includes the sibling defect.
* `2026-09-12` — Documentation is three layers, not one: moduledoc + Credo
  check + ADR amendment. Prose alone is exactly what failed: ADR-023 said the
  right thing about durability and the wrong thing about mpv, and nothing
  caught it for six months.

## Open decisions

* **Name for the shared seam.** Proposed but **not confirmed**:
  `MediaCentaur.Platform.DetachedProcess` — names what it produces (a process
  detached from this app's lifetime) rather than how it does it, and sits with
  the existing `Platform.*` seams. Ask before building; naming is the owner's.

## Next steps

Test-first throughout (`automated-testing`); the red test for each step is
named below.

1. **The seam.** Create the shared detached-spawn module under `Platform.*`
   (pending the name). Move `Apps.Launcher.spawn_spec/1` into it — it is
   already pure and unit-tested, so it is the right starting point. Measure
   whether a portable double-fork removes the `setsid` dependency for macOS;
   if not, give the seam a macOS impl. *Red test:* the spawned process is not
   a child of the VM.
2. **mpv through the seam.** Replace `Port.open` in `mpv_session.ex:407`.
   Drop `:exit_status` handling (`:332`) and the `exit_status` field's use in
   classification (`:1148`), leaving `{:tcp_closed, _}` (`:326`) as the sole
   exit signal. *Red test:* an `MpvSession` whose socket closes finalizes
   exactly as one whose port exited used to.
3. **The unit.** `defaults/media-centaur-dev.service:46` → `KillMode=process`,
   matching `defaults/media-centaur.service:24`. Applying it needs
   `scripts/install-dev`, which regenerates the unit and **restarts the
   service — costing the owner their playback one final time.** Say so before
   running it. The machine's drop-in (`…/media-centaur-dev.service.d/local.conf`)
   sets no `KillMode`, so the default governs and the drop-in survives
   regeneration.
4. **Verify recovery actually fires.** The whole point. Start playback, restart
   the service, confirm mpv keeps playing *and* that
   `recovery: found live session` appears — a line this codebase has never
   emitted. This is the completion signal; steps 1–3 are unverified without it.
5. **Document.** Three layers — see *Completion criteria*.
6. **`Apps.Launcher`.** Route it through the seam and correct its moduledoc.
7. **Wiki + CHANGELOG.** User-visible: playback survives updates. Likely
   *Troubleshooting* and whichever *Using Media Centaur* page covers playback.

## Completion criteria

* An mpv started by Media Centaur survives `systemctl --user restart
  media-centaur-dev`, still playing, with the remote still driving it.
* `recovery: found live session` appears in the journal after that restart,
  and the reattached session resumes progress tracking. **Zero occurrences in
  30 days is the baseline** — one occurrence is the proof.
* An app launched from `/apps` survives the same restart.
* A Credo check refuses `Port.open({:spawn_executable, …})` anywhere but the
  one detached-launch seam, and fails on a deliberately re-introduced port.
* `MpvSession`'s moduledoc states: mpv's lifetime is the viewer's; the port is
  forbidden and why; both kill mechanisms with their measured results; and
  that exit is detected by socket close. Anyone touching mpv meets these facts
  without going looking.
* ADR-023 carries a dated amendment correcting its MpvSession row, so the
  false premise cannot be read as current.
* `Apps.Launcher`'s moduledoc no longer claims survival it does not deliver.
* `mix precommit` green; wiki updated.

## Pointers

* `lib/media_centaur/playback/mpv_session.ex` — `:407` the port, `:326`
  `tcp_closed`, `:332` `exit_status`, `:77` the exit-signal comment, `:1099`
  the cleanup branch that is currently dead code.
* `lib/media_centaur/playback/session_recovery.ex` — the reattach scan that has
  never found anything.
* `lib/media_centaur/playback/supervisor.ex:31` — where recovery is started.
* `lib/media_centaur/apps/launcher.ex` — the existing detached spawn, and the
  moduledoc claim to correct.
* `defaults/media-centaur-dev.service:46` / `defaults/media-centaur.service:24`
  — the two `KillMode` values.
* [ADR-023](../decisions/architecture/2026-03-06-023-durable-process-design.md)
  — the record to amend.
* `docs/mpv.md`, and the `mpv-extensions` skill — mpv Lua scripts and key
  bindings, the layer the owner's remote actually drives.
