---
description: Review the live Status-page issues and, for each, decide if it should be surfaced at all / differently / is fine as-is, then follow up with system fixes for the conditions that created it.
argument-hint: "[subsystem | incident-ref (optional)]"
allowed-tools: Bash, Read, Edit, Write, Grep, AskUserQuestion, Skill, mcp__tidewave__project_eval
---

# Resolve Status Issues

Review the status issues in the currently running app and, for each, determine if:

1. the message should show up in the issues section at all, should be surfaced
   another way, or was surfaced perfectly as-is.
2. the error is showing up in the wrong category, and if so whether there's an
   appropriate / reasonable way to ensure that it shows up in the correct
   category. A category is the board's bucket: the **component** the incident
   is filed under (`nostr`, `social`, `pipeline`, …) and its **kind** (a `:log`
   incident minted from a warning line vs a `subsystem` fault raised by an
   assessor, `subsystem:<component>:<kind>`). Typical miscategorisation: a
   transport-layer warning (`:nostr` "lost <relay>") filed as its own log
   incident when the condition it describes is the Social subsystem's relay
   fault, so the same event shows twice under two components — or a wire
   subsystem's line landing under a component the user doesn't recognise.
   "Reasonable" means fixing it at the seam that produced it (the `Log`
   component tag, the assessor that raises the fault, the fingerprint /
   headline) — not a display-side remap.
3. we should follow up with any fixes to the system to account for the conditions
   that created the issue.

Before implementing any fix — a recategorisation included — run the
**`unify_design`** skill on the affected slice, so the fix lands as one coherent
design rather than a bolt-on.

Be aware that we will see mid-development issues pop up — there's a non-zero
chance the issue comes from live-reloading partially-developed code changes.
Recognise those and don't treat them as real faults.

If you need to develop any tooling to easily interact with the status issues
system, then please do — resolving status issues will be a common occurrence, so
build out any infra necessary.

`$ARGUMENTS` may narrow the scope to a subsystem or a single incident; default is
everything.

---

Load the **`troubleshoot`** skill for the incident model. This machine runs the
**dev instance as the sole daily driver** (port 2160), so reach the running node
through **Tidewave MCP** (`mcp__tidewave__project_eval`) — not `scripts/troubleshoot`
or `mc-rpc`, which target the now-disabled prod release. Evaluate the same
diagnostics functions directly:

- **Read the board:** `MediaCentaur.ErrorReports.list_buckets()` — exactly what the
  Status page shows (or `MediaCentaur.Diagnostics.issues()` for the grouped view).
- **Dump one:** `MediaCentaur.Diagnostics.incident("<fingerprint>")`.
- **Dismiss noise:** `MediaCentaur.ErrorReports.dismiss(["<fingerprint>", ...])`
  (or `MediaCentaur.Diagnostics.dismiss(:all)` to clear the board).

Durable minting is gated on `:durable_diagnostics`, which the dev daily-driver
service enables — so incidents accrue here normally. For the category check,
read where the line was minted: `MediaCentaur.Diagnostics.incident/1` shows the
`component` and `module`, `MediaCentaur.Log` macros carry the component tag,
and `lib/media_centaur/error_reports/fingerprint.ex` / `buckets.ex` decide the
bucket. Then, in order: **`unify_design`** on the slice, **`automated-testing`**
plus the relevant thinking skill before writing any fix (test-first); apply code
changes live by editing source (the dev server recompiles on the next request,
or `systemctl --user restart media-centaur-dev`).
