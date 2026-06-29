---
description: Review the live Status-page issues and, for each, decide if it should be surfaced at all / differently / is fine as-is, then follow up with system fixes for the conditions that created it.
argument-hint: "[subsystem | incident-ref (optional)]"
allowed-tools: Bash, Read, Edit, Write, Grep, AskUserQuestion, Skill
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

Load the **`troubleshoot`** skill — it has the incident model and the CLI for
reading/dumping/dismissing issues. Start from `scripts/troubleshoot issues`
(exactly what the Status page shows, grouped by subsystem); then
`incident <fingerprint>` to dump one, and `dismiss <fingerprint|all>` to clear
noise. Load **`automated-testing`** plus the relevant thinking skill before
writing any fix (test-first). The prod node (`:2160`) is the source of truth —
durable minting is prod-only.
