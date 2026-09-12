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
and has **never once run**, because mpv dies on every restart of this
machine's dev unit. Make mpv survive the restart, verify recovery finally
fires, and document the facts where the next person touching mpv will meet
them — prose alone is what failed here.

## Status

**Complete (Minimal scope) — 2026-09-12.** Premise corrected by measurement
(see *Correction*), owner chose the Minimal scope, shipped and verified
end-to-end. The dev unit now ships `KillMode=process`; the false MpvSession
and `Apps.Launcher` moduledocs are corrected; ADR-023 carries a dated
amendment. The `DetachedProcess` seam / port removal / Credo check were
**declined** — the measurement showed they buy no survival benefit.

**Verification (this machine, live dev service under the new unit):**

* `KillMode=process` confirmed live (`systemctl --user show`).
* Recovery fired for the first time ever. A stub mpv IPC socket left in the
  socket dir across a `systemctl --user restart media-centaur-dev` produced,
  in the journal:
  `recovery: found live session …` → `session started` →
  `reconnected to existing mpv via …sock` → `recovered session`. The reattach
  used IPC only; no fresh mpv launched; the bogus session finalized clean (no
  `PlaybackFailed`, no incident). This is the line the campaign named as its
  completion signal — 0 occurrences in the prior 30 days.
* Survival is mechanism-faithful from the 2×2: a direct BEAM port child
  (mpv's exact spawn shape) survives `systemctl stop` under `KillMode=process`.
* `mix precommit` green (one unrelated pre-existing `SearchSessionTest`
  concurrency flake; 15/15 in isolation).

**No end-user-facing change.** End users run the prod release, whose unit
already shipped `KillMode=process` — mpv already survived a restart for them.
Only this contributor dev box was affected. So: no CHANGELOG entry, no wiki
change (the wiki already states mpv reconnects across a restart, which was
true for prod and is now true here).

## Correction (2026-09-12): the port is not a kill mechanism

The campaign originally claimed **two** independent kill mechanisms — the
BEAM port (`erl_child_setup` SIGKILLs port children on VM halt) and the
cgroup (`KillMode=mixed`). The port claim was an **inference from Erlang
docs, never measured** — the very sin this campaign was written to warn
against. It is false on this machine.

Measured on this box (Elixir 1.20.4 / OTP 29), each cell = a BEAM under a
transient `systemd-run --user` unit that spawns a long-lived child, then
`systemctl --user stop` (the real SIGTERM + orderly-shutdown + KillMode
path, not a bare `:erlang.halt()`), deterministic across three runs:

| Spawn technique | `KillMode=mixed` (dev today) | `KillMode=process` (prod) |
|---|---|---|
| Direct BEAM port — mpv's current pattern (`:exit_status`, `:stderr_to_stdout`, port never closed) | **KILLED** | **SURVIVED** |
| `setsid --fork` detached grandchild | **KILLED** | **SURVIVED** |

Consequences:

* **The port does not bind mpv's lifetime.** A direct port child survives a
  restart whenever the cgroup does not kill it. `:erlang.halt()` on its own
  also leaves the child alive (OTP 29 reparents it to init).
* **setsid buys no survival.** It does not escape the cgroup (confirming the
  earlier row) and matches the port in both KillMode settings.
* **The only lever that matters is `KillMode`.** `mixed → process` on the
  dev unit is necessary *and* sufficient for mpv (and every `/apps` process)
  to survive a restart.
* **Prod already survives.** `defaults/media-centaur.service` ships
  `KillMode=process`, so mpv already outlives a restart there. "0 recoveries
  in 30 days" is fully explained by this machine running the **dev** unit
  (`mixed`), which kills mpv every restart — the port was never the cause.
* **`Apps.Launcher` is not broken by its setsid.** Its moduledoc claim is
  false only under the current dev unit (`mixed`); it becomes true the moment
  `KillMode` is flipped, with no code change to the launcher.

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

* **Scope, reopened by the correction above.** The measurement removed the
  functional reason for the seam. Two honest paths:
  * **Minimal.** Flip the dev unit's `KillMode` to `process`, verify recovery
    fires, correct the false moduledocs (MpvSession + `Apps.Launcher`), and
    amend ADR-023 to the measured truth. Drop the `DetachedProcess` seam, the
    port removal, and the Credo check. Fully fixes the measured problem;
    simplest.
  * **Full.** Everything in *Minimal*, plus route mpv + `Apps.Launcher`
    through the `DetachedProcess` seam, remove the port, and add the Credo
    check — on architectural/robustness grounds (mpv's lifetime is the
    viewer's; eliminate the low SIGPIPE-on-broken-pipe risk at BEAM
    shutdown), even though none of it is required for survival.

  Owner's call — this is scaling the approved work down, which is not the
  model's to decide.

## Settled decisions

* `2026-09-12` — **Seam name (if the seam is built): `MediaCentaur.Platform.DetachedProcess`**
  (owner chose it from `DetachedProcess` / `ExternalProcess` / `DetachedSpawn`).
  Names what it produces — a process detached from this app's lifetime — and
  sits with the existing `Platform.*` seams. Contingent on the *Full* scope.
* `2026-09-12` — **The port is not a kill mechanism (measured).** See
  *Correction* above. `KillMode=mixed→process` on the dev unit is the
  necessary and sufficient fix; the seam is now optional.

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
