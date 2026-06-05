# Public-issue error reporting

**Date:** 2026-06-05
**Status:** Approved (design)
**Supersedes:** [`2026-06-01-consent-flow-design.md`](2026-06-01-consent-flow-design.md) — the private-inbox submission model and its privacy promises are withdrawn.

## Problem

The in-app error reporter promised users their report goes to *"a private inbox
only the core dev team can read — never posted publicly."* Honoring that promise
requires a server-side credential to file issues in a private repo. We found:

1. The credential was never wired — `:diagnostics_report_token` is `nil` in every
   environment, so auto-submission **never executed anywhere**; the copy-paste
   fallback was the only live path (latent bug, partially addressed
   2026-06-05 in `000bae42`, reverted by this work).
2. The only ways to make centralized submission work are (a) a server relay we
   run, or (b) embedding a shared token in the public release. Embedding is
   disqualified: **GitHub has no create-issue-without-read credential**, so any
   embedded token lets anyone who extracts it (open-source binary) read *every*
   user's submitted report — a silent breach of the very privacy promise.

Decision: **drop the privacy promise.** Reframe the feature honestly as *"this
will be posted as a public GitHub issue, here is exactly what — review and edit
it."* Redaction + user review carry the safety, not a privacy guarantee.

## Model

The reporter produces a **redacted** report, the user **reviews and edits** it,
then posts it as a **public GitHub issue under their own GitHub login**, in their
browser. No token, no relay, nothing server-side, no auto-submission.

```
Incident → ReportPayload.build (redacted markdown)
        → 3-step consent modal (review + edit the exact text)
        → "Review & post to GitHub":
             • copy full report body to clipboard
             • open  github.com/<repo>/issues/new?title=…&labels=…  (user posts as themselves)
        → best-effort persist the :user incident locally (unchanged)
```

Reporting is now available to anyone with a GitHub account; a standalone
**Copy to clipboard** button remains as the no-GitHub escape hatch.

## Components

### New / repurposed

- **`IssueUrl.new_issue_url/2`** (pure) — builds
  `https://github.com/<repo>/issues/new?title=<enc>&labels=<enc>&body=<enc>`.
  Title from `format_title/1` (already redacted, ≤140). Body param carries a
  short *"Paste your report below — it's on your clipboard 👇"* placeholder (the
  full report goes via clipboard, never the URL, sidestepping length limits).
  Labels `incident,auto-reported` (best-effort — GitHub ignores `labels=` for
  reporters without triage rights; maintainer relabels). This revives the
  module's original URL-building purpose (its moduledoc flagged itself as a
  retire candidate; instead it gets its job back).
- **Repo target** — `config :media_centaur, :diagnostics_issues_repo,
  "media-centaur/media-centaur"` (the public repo; overridable for tests/showcase).
- **Result view actions** — reuses the existing `CopyButton` hook (writes the
  report body to the clipboard) plus a plain anchor (`<a href={issue_url}
  target="_blank">`) that opens the prefilled new-issue page. No new JS hook.

### Rewritten

- **`ConsentComponents`** — messaging flip:
  - Step 1: replace the four "promises" (incl. *"only the core dev team can see
    it — never posted publicly"*) with public-transparency framing: *"This will
    be posted as a public GitHub issue so it can be tracked and fixed. We've
    removed file paths, API keys, IP addresses and emails — and you'll see and
    can edit the exact text before anything is posted."*
  - Step 3: replace the private-inbox box with a public-post restatement; the
    consent checkbox wording becomes *"I've reviewed this and I'm posting it
    publicly on GitHub."*
- **`StatusLive.ReportModal`** — the `"send"` handler no longer calls a transport.
  It assembles the redacted body, best-effort persists the `:user` incident, then
  shows a result view with **Copy** + **Post to GitHub** actions wired to the
  `CopyButton` hook + anchor (see above). Button label → *"Review & post to GitHub."* The `{:ok,url}` /
  `{:fallback,text}` result shapes are gone.
- **`ErrorReports`** — remove `submit_payload/2`, `submit_report/2`,
  `create_user_report/2`'s transport call, and `configured_transport/0`. Keep
  `build_generic_report/0`, `assemble_body/2`, and incident persistence. Add a
  thin entry returning `%{title, body, issue_url}` for the modal. Update moduledoc.

### Removed

- `ErrorReports.GithubTransport` + `github_transport_test.exs`.
- `ErrorReports.ReportTransport` behaviour (only impl was GithubTransport).
- `:diagnostics_report_token` / `:diagnostics_report_repo` config and the
  `runtime.exs` env-var block added in `000bae42`.
- `:diagnostics_transport` indirection.

## Data flow & error handling

- **No network call** in the submission path → no timeout/offline failure mode.
  The previous "couldn't send automatically" fallback ceases to exist; posting is
  always a local clipboard-write + browser-open.
- **Clipboard write fails** (permissions): the report text stays visible in a
  readonly textarea with a "select-all" affordance; the GitHub button still opens
  the new-issue page. Reporting degrades to manual copy, never to a dead end.
- **No GitHub account**: Copy button + the rendered text suffice; the user can
  paste anywhere (forum, email) — but we make no destination promise.

## Testing

- `IssueUrl.new_issue_url/2` — pure unit tests: param encoding (spaces, `#`,
  newlines, unicode), title slice, label list, repo from config.
- `ErrorReports` — unit tests for the new entry shape; incident still persisted.
- `ReportModal` — LiveView tests: stepping, edit propagation, the send handler
  produces the URL + persists the incident (assert on assigns/data, not HTML).
- Delete `github_transport_test.exs` with the module (transport removed; this is
  not a regression-test deletion under ADR-027 — it is removing tests for deleted
  code).
- Stories (MC0009): update `ConsentComponents` step stories and any `ReportModal`
  result-state stories to the new copy + result view.
- Page smoke: Status route unaffected (already covered).

## Out of scope / deferred

- Inline body prefill when short enough (start copy+paste-always; revisit).
- The private-email fallback idea (parked separately, pending an address —
  now moot under the public model unless revived).

## Wiki / docs

User-visible behavior change → update the wiki (Troubleshooting / FAQ): the
reporter now opens a **public** GitHub issue under the user's account; remove any
"private / only the developer can read it" language. Same unit of work.
