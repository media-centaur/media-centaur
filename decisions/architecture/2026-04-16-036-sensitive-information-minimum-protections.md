---
status: accepted
date: 2026-04-16
---
# Minimum protections for sensitive information

## Context and Problem Statement

The application holds credentials (TMDB and Prowlarr API keys, download-client passwords) that once lived as plain strings in `:persistent_term`, the Settings table, the TOML file, request logs, and LiveView assigns, so any `inspect/2` on a containing structure leaked them. The threat is not the network but mundane sharing: a crash dump pasted into an issue, a journal excerpt shared while troubleshooting, a dotfiles repo, an `IO.inspect` in a dev session. A leaked credential must be rotated, so the protections have to be uniform and automatic.

## Decision Outcome

Every sensitive value receives all four protections; a credential without all four is a bug.

1. **Wrapped as `MediaCentaur.Secret`** in `:persistent_term`. `MediaCentaur.Settings.Config` returns a `%Secret{}` for the keys in its `sensitive_keys/0`; callers call `Secret.expose/1` only at the HTTP or external-API boundary. `Secret` overrides `Inspect` to print `#Secret<***>` and deliberately omits `String.Chars`, so accidental interpolation raises instead of leaking.
2. **Redacted from request logs** by `:phoenix, :filter_parameters` (`password`, `api_key`, `secret`, `token` substrings, case-insensitive); `sensitive_params_filter_test.exs` is the regression guard.
3. **Never read from the TOML file.** Sensitive values are entered through Settings and persisted in the Settings table only.
4. **Never placed in LiveView assigns or templates.** A view that needs "is this configured?" carries a `*_configured?` boolean derived via `Secret.present?/1`; the value itself never enters assigns.

Adding a credential does all of the following in one change: add the key to `sensitive_keys/0`; wrap it wherever it enters `:persistent_term`; confirm its form-field name matches a filter pattern (extend the list and the test if not); expose only a `*_configured?` boolean in any view; add the `Secret.expose/1` call at the boundary. When in doubt, classify as sensitive.

### Consequences

* Every secret-using call site carries an explicit `Secret.expose/1`.
* This is not encryption at rest: shell access to the host reads the SQLite file and every credential in it. OS-keyring integration stays out of scope while the audience self-hosts on localhost.
