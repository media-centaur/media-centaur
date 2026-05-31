---
status: planning
started: 2026-05-31
last_updated: 2026-05-31
---
# Download stack: control plane + new repo

## Goal

Mature the download infrastructure (`prowlarr-stack` today) from a
**one-shot installer** into a **managed component with a control plane**, and
ship it as a **new `download-stack` repo** that supersedes `prowlarr-stack`.
The reframe that drives everything: install / configure / reconfigure /
observe / diagnose are the *operational lifecycle* of the stack — a
`curl | sh` installer only ever covers the first. The stack doesn't have a
brittle installer; it has a **missing control plane**, and the installer is
being stretched to do a job it was never shaped for. This campaign builds that
control plane and the thin, versioned seam between the stack and Media Centaur.

**Adding usenet (SABnzbd) is a first-class part of this work**, not a follow-on.
The new repo ships **torrent + usenet** out of the box: the SABnzbd service is
the immediate forcing function for maturing the stack, and it's also the first
real test of the control-plane model (a second client the user toggles in
`stack.toml` rather than re-running an installer). The stack-side SABnzbd
service therefore lands **here**, in the new repo — it is *moved out of* the
[`usenet-download-client`](usenet-download-client.md) campaign's P0, which
assumed it would be bolted onto `prowlarr-stack`.

## The model

Settled in the 2026-05-31 design session. Resumable context — read before
writing code.

**The stack owns its own control plane; Media Centaur stays thin.** The
decisive principle is **change-axis isolation**: MC must change *only* when the
MC↔stack protocol changes, and for no other reason. Adding a fourth download
client, a new VPN provider, a routing toggle — none are protocol changes, so
none may touch MC. Folding a cockpit into MC would wire all of the stack's
reasons-to-change into MC's reasons-to-change. We decline that coupling on
purpose. *(Rejected: MC-as-cockpit — best UX, but it forces MC to churn on
every kind of stack change and hands MC docker privileges + a harder macOS
port.)*

**Three-tier state model — the lens for every "what happens when I move/change
it" question.** The stack carries three kinds of state, each behaving
differently under every transition:
1. **Desired state / config** — VPN choice, creds, storage paths, which
   clients, indexers. Small, portable. *(prowlarr-stack already moves this:
   backup/restore tars `.env` + `config/`, scrubs the old LAN IP, re-patches.)*
2. **App state** — Prowlarr indexer DB, qBittorrent torrent list + active
   seeding, SABnzbd history. Medium, sqlite/internal, **version-coupled to the
   container images**.
3. **Bulk data** — the actual bytes: in-flight, completed-not-imported, and
   still-seeding torrents. Large, on a mount, **entangled with MC's library**
   at the watched-dir handoff. *(prowlarr-stack deliberately never moves this.)*

**v1 contract: drain-before-change.** Downloads must be **completed or removed
before** upgrading or changing config. This deletes the worst tier of
complexity — no live-migration of in-flight downloads or active seeding. The
reconciler renders desired state onto a **quiesced** stack (stop → apply →
restart); it never babysits live Tier-3 state. We enforce/warn on the
precondition (refuse to reconfigure with a non-empty queue, or make the user
confirm the loss). This turns the job from "live-migrate a running system" into
"render desired state onto a drained one" — categorically easier and more
reliable, which was the top priority.

**Control plane is config-as-truth (no bundled web UI).** A single
`stack.toml` is the source of desired state; an `apply` reconciler renders
compose/env and converges a drained stack; a `status`/health surface reports
actual state. VPN routing — the symptom that started the conversation —
becomes a **runtime toggle in `stack.toml`**, not a choice baked at install
time. (Compose already hints at the mechanism: prowlarr-stack toggles the VPN
with a profile overlay + `COMPOSE_FILE`; the choice just got frozen by the
installer instead of staying a live knob. "Make it reconfigurable" is "stop
baking it," not a rewrite.) The schema is designed so a web UI *could* sit on
top later, but we don't build one — the polished "toggle and it just works" UX
for the *acquisition* side lives on MC via the handshake. *(Rejected for v1:
bundled web UI — relocates the exact churn we're avoiding out of MC into the
stack; YAGNI until the file-driven model proves reliable.)*

**Cross-seam observability: a read-only health endpoint MC consumes.** The
nightmare case — "MC says done, file never showed up" — is a *seam* failure
that needs both halves to diagnose (MC: "I grabbed, queue matched, expected a
file in my watched dir"; stack: "qBit reported complete, wrote to
/completed/X"). The stack's control plane exposes a **read-only status
endpoint** (another protocol); MC consumes it to show "stack: healthy / VPN up
/ last completion 3m ago" and deep-link to the cockpit. MC's change surface
stays tiny (moves only if the health contract changes), but the user gets *one
front door*. The seam becomes observable from MC's side without MC owning the
stack.

**MC↔stack provisioning handshake — push-based, versioned, confirm-in-MC.**
This is the protocol seam made concrete and the *one sanctioned reason MC
changes*. During stack install: detect MC on `localhost:2160`, then **POST a
wiring proposal** to MC's provisioning endpoint. MC does **not** auto-apply —
it stages a *pending proposal* and surfaces a card in its own UI ("A download
stack on this host wants to configure acquisition — Prowlarr at …, qBittorrent
at …, watched dir … — Accept / Decline"). The user **Accepts in MC** → MC
writes the config and wires up. The installer reads the outcome (poll the
proposal id, or print "→ approve it in Media Centaur") so it can report
"✓ configured" vs "waiting on approval."
- **Trust model: loopback-only + confirm-in-MC.** Same-host is assumed (v1
  designs for it explicitly). The POST is only a *proposal*; approval happens
  inside MC's own trusted surface, so it doesn't matter that any localhost
  process *can* POST — nothing rewires acquisition until a human says yes *in
  MC*. No shared secret. *(Beats trust-on-first-use: same convenience, but you
  see exactly what's being wired first.)*
- **Payload is a wiring bundle, not "configure Prowlarr."** Because MC's
  `QueueMonitor` polls the download *clients directly* (qBit/SAB APIs), the
  proposal carries **client endpoints + creds + the watched dir**, not just the
  Prowlarr URL + key.
- **Versioned from day one.** The stack announces a handshake schema version;
  MC accepts versions it understands. This endpoint *is* the coupling surface,
  so versioning it is how the seam stays the only thing that moves MC.

**Delivery: new `download-stack` repo, greenfield-with-heritage.** Build a new
repo that ports prowlarr-stack's *proven* parts — the compose topology, the
gluetun kill-switch, the mountpoint / `RequiresMountsFor` hardening, the
backup/restore + cross-machine LAN re-patch logic — but is built around the
control-plane model from the start. Retire `prowlarr-stack` once the new repo
reaches **parity-plus-maturity**. Greenfield beats refactoring in place because
the old repo's *shape* (install-time-baked choices) is exactly what we're
moving away from. The new repo ships **both** clients — qBittorrent (ported)
and **SABnzbd (net-new usenet service)** — registered as Prowlarr's two
protocol-routed download clients, with SABnzbd's completed dir landing inside
MC's watched paths and placed *outside* the gluetun tunnel (usenet is
SSL-to-provider, no P2P leak — same posture as qBit today). The stack-side
SABnzbd service is the [`usenet-download-client`](usenet-download-client.md)
campaign's P0, relocated here; that campaign keeps the **MC-side** work (the
one-client → set-of-clients refactor + the SABnzbd driver).

## Status

Design settled 2026-05-31; no code yet. ADR-052 (the boundary decision) is the
first deliverable.

## Decisions made

Append-only log.

* `2026-05-31` — **Stack owns the control plane; MC stays thin** (change-axis
  isolation). *(Rejected: MC-as-cockpit.)* (ADR-052 planned)
* `2026-05-31` — **The problem is a missing control plane, not a brittle
  installer.** Install/configure/observe/reconfigure are the stack's
  operational lifecycle; the installer only covers install.
* `2026-05-31` — **Three-tier state model** (config / app-state / bulk-data) is
  the lens for every move/change/migrate question.
* `2026-05-31` — **v1 contract: drain-before-change.** No live-migration of
  in-flight downloads or seeding; reconciler renders onto a quiesced stack;
  precondition enforced/warned.
* `2026-05-31` — **Config-as-truth control plane**: `stack.toml` +
  `apply` reconciler + `status`/health; VPN routing becomes a runtime toggle.
  *(Rejected for v1: bundled web UI.)*
* `2026-05-31` — **Read-only health endpoint MC consumes** for one front door;
  keeps MC's change surface tiny.
* `2026-05-31` — **Provisioning handshake**: push proposal → stage → confirm in
  MC. Loopback-only + confirm-in-MC; same-host assumed; versioned; payload is
  the full wiring bundle (clients + creds + watched dir).
* `2026-05-31` — **New `download-stack` repo supersedes `prowlarr-stack`**,
  porting its proven parts; old repo removed at parity-plus-maturity.
* `2026-05-31` — **Adding SABnzbd (usenet) is first-class to this campaign**, not
  a follow-on: the new repo ships torrent + usenet out of the box, and the
  stack-side SABnzbd service is relocated here from `usenet-download-client`'s P0
  (that campaign keeps the MC-side driver + multi-client refactor).
* `2026-05-31` — **Rename off "prowlarr-stack"** — Prowlarr is one component,
  not the identity.

## Next steps

Phased; each phase ships something real. The handshake MC-receiver (P4) is
independently valuable and can be sequenced early.

1. **P0 · ADR-052 + repo scaffold.** Write ADR-052 (control-plane-in-stack /
   thin versioned MC↔stack seam / drain-before-change) — it **amends ADR-035's**
   single-stack assumptions. Create the new `download-stack` repo; settle the
   name.
2. **P1 · Parity port + SABnzbd.** Bring prowlarr-stack's proven pieces into the
   new repo (compose topology, gluetun kill-switch, mountpoint /
   `RequiresMountsFor` hardening, backup/restore + LAN re-patch) **and add the
   net-new SABnzbd usenet service** (outside the VPN tunnel, completed dir inside
   MC's watched paths, registered as Prowlarr's second protocol-routed client).
   Baseline = behavioral parity with prowlarr-stack *plus* working usenet. This
   absorbs the [`usenet-download-client`](usenet-download-client.md) campaign's
   stack-side P0.
3. **P2 · Control plane.** `stack.toml` as the single source of desired state;
   `apply` reconciler (drain-aware: stop → render compose/env → restart);
   **VPN routing as a runtime toggle** (profile driven by toml, not install-
   baked). Enforce/warn the drain-before-change precondition.
4. **P3 · Health endpoint.** Read-only `status` surface probing containers, VPN
   reachability/kill-switch, the watched dir, and the Prowlarr→client wiring.
   Shapes the contract MC will consume.
5. **P4 · Provisioning handshake (MC-side, this repo).** MC endpoint:
   loopback-only receiver, stage pending proposal, confirm-in-MC card, write +
   wire on accept, expose outcome to the installer. Versioned schema. Stack
   installer side: detect MC on `:2160`, POST the wiring bundle, report
   outcome.
6. **P5 · MC consumes health.** Surface stack health + last-completion in MC and
   deep-link to the cockpit — one front door for the seam failure.
7. **P6 · Cutover.** Reach parity-plus-maturity; migrate docs/wiki/install
   one-liners and the references in `install-repro-matrix` +
   `usenet-download-client`; deprecate and **remove `prowlarr-stack`**.

## Risk surface

`(exists)` works today · `(extends)` grows existing code · `(net-new)` new.

1. **Two-repo cutover drift** *(net-new)* — the new repo must reach real parity
   (backup/restore, VPN modes, hardening) before the old one is removed, or
   users lose working behavior. Mitigation: P1 parity baseline is explicit;
   remove only at parity-plus-maturity.
2. **Reconciler partial-apply** *(net-new)* — a half-applied `apply` (rendered
   compose but failed restart) must be detectable and re-runnable, not leave a
   wedged stack. Idempotent apply + a `status` that reports drift.
3. **Handshake is privileged** *(net-new)* — anything on localhost can POST a
   proposal. Safety rests entirely on confirm-in-MC; the receiver must never
   auto-apply, and the card must show the exact wiring before accept.
4. **Payload completeness** *(extends)* — MC polls clients directly, so a
   proposal missing a client endpoint/cred silently half-wires acquisition.
   Validate the bundle MC-side before staging.
5. **Health-contract coupling** *(net-new)* — the status endpoint is a protocol
   MC depends on; unversioned changes to it become a hidden way to break MC.
   Version it like the handshake.
6. **Drain-before-change is a user contract, not a guarantee** *(extends)* —
   users will reconfigure with a live queue. Enforce (refuse) or loudly confirm
   the data loss; don't silently stop a running download.

## Completion criteria

* New `download-stack` repo at parity-plus-maturity: backup/restore, VPN
  modes, mountpoint hardening all working, **plus a working SABnzbd usenet
  service** (torrent + usenet out of the box), built on the control-plane model.
* `stack.toml` is the single source of desired state; `apply` reconciles a
  drained stack; **VPN routing is a runtime toggle**, not an install-time fork.
* Read-only `status`/health endpoint reports container / VPN / watched-dir /
  wiring state; MC consumes it and surfaces one front door for the seam.
* Provisioning handshake works end-to-end on one host: installer detects MC,
  POSTs the wiring bundle, MC stages it, user accepts in MC, acquisition is
  wired — versioned, loopback-only, confirm-gated.
* Drain-before-change precondition is enforced/warned.
* ADR-052 written (amends ADR-035); docs/wiki/install one-liners migrated.
* `prowlarr-stack` deprecated and removed; references in sibling campaigns
  updated.

## Pointers

* **Current stack** — `~/src/media-centaur/prowlarr-stack/`:
  `docker-compose.yml` (gluetun + Prowlarr + FlareSolverr + qBittorrent),
  `docker-compose.qbt-vpn.yml` (the VPN-routing overlay — the toggle to lift
  into `stack.toml`), `setup` (mountpoint hardening, `--reconfigure`),
  `backup`/`restore` (Tier-1 portability + LAN re-patch), `install.sh`,
  `update`, `README.md`.
* **MC↔stack seam (MC side)** — `lib/media_centaur/config.ex`
  (`download_client_*` ~L48, MC port `2160` ~L417), `search/prowlarr.ex`
  (Prowlarr API client), `downloads/download_client/dispatcher.ex` +
  `qbittorrent.ex` (MC polls clients directly), `downloads/queue_monitor.ex`.
  The provisioning endpoint is net-new web surface.
* **ADRs** — [ADR-035](../decisions/architecture/2026-04-15-035-acquisition-prowlarr-integration.md)
  (Prowlarr integration — **ADR-052 amends its single-stack assumption**),
  [ADR-037](../decisions/architecture/2026-04-16-037-acquisition-integration-scope.md)
  (integration scope), [ADR-043](../decisions/architecture/2026-05-10-043-acquisition-split.md)
  (Search/Downloads split), [ADR-042](../decisions/architecture/2026-05-10-042-multi-session-campaigns.md)
  (campaign convention).
* **Sibling campaigns** —
  [`usenet-download-client.md`](usenet-download-client.md) (the SABnzbd service
  lands in the new repo; the multi-client refactor is MC-side and independent),
  [`install-repro-matrix.md`](install-repro-matrix.md) (reproducible installs —
  its prowlarr-stack references move to the new repo at cutover),
  [`media-search-tmdb-acquisition.md`](media-search-tmdb-acquisition.md) (the
  planner that drives acquisition over this infrastructure).
