---
status: accepted
date: 2026-03-03
---
# No magic numbers

## Context and Problem Statement

Numeric and string literals scattered through implementation code are hard to find, hard to change, and give no indication of *why* that value was chosen. When the same value appears in multiple places, they drift apart silently. Worse, some values are policy decisions that users should be able to override — but burying them in code makes that impossible without a code change.

## Decision Outcome

Chosen option: "Extract literals to the appropriate level of configuration", because it makes values discoverable, documents intent, and puts policy decisions in the hands of the people who should own them.

**Rules:**

1. **Name every significant literal.** Extract numbers, durations, thresholds, sizes, and path fragments into module attributes (`@batch_size`, `@poll_interval_ms`, `@max_retries`). The name documents intent; the value is easy to find and change.
2. **Promote to app config when the value is environment-sensitive.** If a value should differ between dev, test, and prod — or between deployments — it belongs in `config/*.exs` and is accessed via `Config.get/1`. Examples: timeouts, batch sizes, rate limits.
3. **Promote to user config when the value is a policy decision.** If the user should reasonably want to tune it, add it to `Config.get/1` with a default in `defaults/backend.toml` and a comment explaining what it controls. Examples: `auto_approve_threshold`, `file_absence_ttl_days`.
4. **Don't over-extract.** Some literals are inherently fixed and well-understood in context: `0`, `1`, `""`, list indices, HTTP status codes (`200`, `404`), and mathematical constants. Use judgment — if the meaning is immediately obvious and the value will never change, leave it inline.
5. **Keep `defaults/backend.toml` complete.** Every key recognized by `Config` must appear in the defaults file with a sensible value and a comment. The defaults file is the documentation for user-facing configuration.

### Consequences

* Good, because intent is documented — `@max_retries` explains what `3` means in context
* Good, because changing a value requires editing one place, not grepping the codebase
* Good, because user-tunable policy decisions are discoverable in `defaults/backend.toml`
* Good, because the three-tier model (module attribute → app config → user config) gives clear guidance on where each value belongs
* Bad, because it requires judgment calls on which tier a value belongs to — not every case is obvious
