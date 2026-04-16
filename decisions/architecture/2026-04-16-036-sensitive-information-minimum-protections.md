---
status: accepted
date: 2026-04-16
---
# Minimum protections for sensitive information

## Context and Problem Statement

The system holds three credentials today: TMDB API key, Prowlarr API key, qBittorrent password. More will arrive (Sonarr/Radarr keys if we ever pull from them, OAuth tokens, S3-style cloud sync credentials). Before adding `:download_client_password`, every credential lived as a plain string in `:persistent_term`, in the SQLite Settings table, in the TOML config file, in `Plug.Logger` request logs, and inside `socket.assigns` — anywhere `inspect/2` was called on a containing structure, the value leaked.

The threat model is not network adversaries (the app binds to loopback by default and HTTPS handles wire concerns when needed). The threats are mundane and high-frequency:

  * Crash dumps that include `socket.assigns.config` get pasted into bug reports / Discord / GitHub issues.
  * `journalctl` output (full request params at info level) gets shared during troubleshooting.
  * The TOML file ends up in a dotfiles repo backed up to GitHub.
  * `IO.inspect(config)` during dev / IEx accidentally writes the secret to a log.

These leaks are silent and irreversible — once a credential is on a public surface, it must be rotated.

We need a uniform floor of protection that every new credential gets automatically, plus an explicit gate so adding a new credential cannot ship without thinking about it.

## Decision Outcome

Every value classified as sensitive MUST receive all four protections below. There is no opt-out: a credential without all four is a bug.

1. **Wrapped as `MediaCentarr.Secret`** in `:persistent_term`. `Config.get/1` returns `%Secret{}` for sensitive keys; callers must call `Secret.expose/1` at the HTTP / external-API boundary. The `Secret` struct overrides `Inspect` to print `#Secret<***>` and intentionally does not implement `String.Chars` so accidental interpolation crashes loudly instead of leaking. The list of sensitive keys lives at `MediaCentarr.Config.sensitive_keys/0`.

2. **Covered by `:phoenix, :filter_parameters`** in `config/config.exs` so `Plug.Logger` and `Phoenix.Logger` redact the value to `[FILTERED]` in request and event logs. The current pattern set (`~w(password api_key secret token)`) covers any field whose name contains one of these substrings (case-insensitive). New credentials must either match an existing pattern or extend the list. `test/media_centarr_web/sensitive_params_filter_test.exs` is the regression guard.

3. **Never readable from the TOML config file.** Sensitive values are entered through the Settings UI only and persisted to the SQLite Settings table. The TOML's job is non-secret structural config (paths, URLs, intervals). Eliminating the TOML path eliminates the dotfiles-backup leak class entirely. The `download_client_password` removal is the precedent.

4. **Never placed in LiveView assigns or template variables.** LV assigns end up in crash dumps. Templates that need to know "is this configured?" use a `*_configured?` boolean derived via `Secret.present?/1` in `load_config/0`; the secret itself never enters the assigns map.

### The gate

Adding a new sensitive value to the codebase MUST do all of the following in the same change. Reviewers should reject any PR that adds a credential without satisfying every one:

  1. Add the key to `MediaCentarr.Config.sensitive_keys/0`.
  2. Wrap the value with `Secret.wrap/1` everywhere it enters `:persistent_term` (TOML defaults, `merge_toml`, `load_runtime_overrides`, `update/2`).
  3. Confirm the form-field name matches one of the substrings in `:phoenix, :filter_parameters`. If it doesn't, extend the list AND update `sensitive_params_filter_test.exs`.
  4. Decide whether the TOML path is acceptable. Default: NO. If you genuinely need TOML loading, justify it explicitly in the PR description and in this ADR's appendix.
  5. In any LiveView that surfaces the configured-state of the value, expose only a `*_configured?` boolean — never the value itself.
  6. Update `Secret.expose/1` call sites at the HTTP/external boundary.

When in doubt, classify the value as sensitive. False positives cost a `Secret.expose/1` call; false negatives leak credentials.

### Consequences

* Good, because crash dumps no longer leak credentials. The four protections compose — defeating the leak requires a deliberate `Secret.expose/1` followed by writing the exposed value somewhere observable.
* Good, because the `String.Chars` omission turns "I forgot to expose" from a silent leak into a runtime crash with a clear stack trace.
* Good, because removing TOML support for sensitive keys eliminates the highest-likelihood leak path (dotfiles in version control) without affecting non-sensitive structural config.
* Good, because the explicit `sensitive_keys/0` list and the gate checklist make adding a credential a discoverable, reviewable event rather than an oversight.
* Bad, because every secret-using call site needs an `Secret.expose/1` call, slightly more verbose than reading a raw string. The trade-off is acceptable — the verbose form is the secure form.
* Bad, because the `Secret` struct is project-specific, not a community-vetted library. If a load-bearing flaw is found, we have to fix it ourselves. Mitigation: the implementation is small (one struct, three functions, one Inspect impl) and has direct test coverage.
* Bad, because this is not cryptographic protection. An attacker with shell access on the host reads the SQLite file directly and gets every credential. The arr-stack peers (Sonarr, Radarr, Prowlarr) accept the same trade-off. Closing this gap requires OS-keyring integration (libsecret) and is out of scope until we ship to non-localhost setups by default.

## Out of scope (for now)

  * Encryption-at-rest for the Settings DB. Possible future work: derive a key from `/etc/machine-id` or a separate file with `0600` perms.
  * OS keyring integration (gnome-keyring/kwallet via libsecret). High value if this app ever gets shipped as a packaged install for non-developers; not worth the dependency complexity for the current developer-self-host audience.
  * Audit log of who/when read a secret. Single-user app today; revisit if this grows multi-user.

## Implementation

  * `lib/media_centarr/secret.ex` — the `Secret` struct.
  * `lib/media_centarr/config.ex` — `sensitive_keys/0`, wrap-on-load, wrap-on-update, password no longer parsed from TOML.
  * `config/config.exs` — `:phoenix, :filter_parameters` configured.
  * `lib/media_centarr/tmdb/client.ex`, `lib/media_centarr/acquisition/prowlarr.ex`, `lib/media_centarr/acquisition/download_client/qbittorrent.ex` — the three boundary call sites that `Secret.expose/1`.
  * `lib/media_centarr_web/live/settings_live.ex`, `lib/media_centarr_web/live/status_live.ex` — `*_configured?` booleans replace raw secrets in assigns.
  * `test/media_centarr/secret_test.exs`, `test/media_centarr_web/sensitive_params_filter_test.exs` — protection regression tests.
