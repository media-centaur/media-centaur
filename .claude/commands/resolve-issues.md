---
description: Review the live Status-page issues and, for each, decide if it should be surfaced at all / differently / is fine as-is, then follow up with system fixes for the conditions that created it.
argument-hint: "[subsystem | incident-ref (optional)]"
allowed-tools: Bash, Read, Edit, Write, Grep, AskUserQuestion, Skill, mcp__tidewave__project_eval
---

# Resolve Status Issues

Review the status issues in the currently running app and, for each, determine if:

1. the message should show up in the issues section at all, should be surfaced
   another way, or was surfaced perfectly as-is.
2. we should follow up with any fixes to the system to account for the conditions
   that created the issue.

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
service enables — so incidents accrue here normally. Load **`automated-testing`**
plus the relevant thinking skill before writing any fix (test-first); apply code
changes live by editing source (the dev server recompiles on the next request,
or `systemctl --user restart media-centaur-dev`).
