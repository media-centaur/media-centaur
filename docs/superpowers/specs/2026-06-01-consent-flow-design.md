> **Superseded 2026-06-05** by [`2026-06-05-public-issue-reporting-design.md`](2026-06-05-public-issue-reporting-design.md). The private-inbox model and its privacy promises are withdrawn; reports now post to a public GitHub issue.

# Consent Flow — Incident Report Submission (design)

**Date:** 2026-06-01
**Status:** approved design, pre-implementation
**Campaign:** [`campaigns/observability-dashboard.md`](../../../campaigns/observability-dashboard.md) — Phase 4, Milestone 2 (reporting rebuild)
**Supersedes:** the master spec's vaguer "guided 3-step consent modal (… manual
redaction …)" line ([2026-05-31 spec](2026-05-31-observability-dashboard-design.md) D3), and the throwaway
structured-section proposal in `mockups/observability/CONSENT-FLOW-PROPOSAL.md`.

## Context

Phase 3 shipped the submission backbone: `ErrorReports.submit_report/2` files an
incident report to a private repo via the GitHub REST API, falling back to a
copyable bundle on no-token/offline (`{:ok, url} | {:fallback, bundle}`). The
`/status` report modal was corrected for that private path (`8b819993`) but is
still an **interim single-screen confirm** — not the guided consent flow.

This spec defines that flow: the user-facing review-and-consent experience that
sits in front of `submit_report`.

## Decisions (from the 2026-06-01 brainstorm)

- **D1 — Removal exists only for privacy.** The `Redactor` already strips paths,
  keys, IPs, emails, and UUIDs at capture. The residual risk is sensitive text
  *inside otherwise-useful free text* — a private title, a username — that the
  redactor cannot classify generically.
- **D2 — Edit the exact outgoing text, not structured toggles.** Because the
  leak is words *inside* a line the user wants to keep, "remove a card/section"
  is the wrong model. The user edits the literal text that will be sent; what
  they see is byte-for-byte the payload.
- **D3 — The entire payload (title + body) is editable**, facts included — the
  most literally honest model and the simplest mental model.
- **D4 — Finding-assist is a clear note only.** No token highlighting (fuzzy
  heuristic, risk of false "all caught", extra build). YAGNI.
- **D5 — Add an optional user narrative** — the human's own account of what
  happened, in their words.
- **D6 — Incident-anchored.** Every report starts from a *detected* incident
  ("Report this" in the drill-in, "Report errors" on the board). The standalone
  "something else seems wrong" (`:user`-origin from scratch) entry point and its
  `Store` create-path remain **Milestone 4**.
- **D7 — Three steps**, because they are now meaningful: your report → the
  attached technical context → consent & send (not the earlier artificial
  promises/cards/consent split).

## The flow — a 3-step `LiveComponent` modal

Launched pre-loaded with the originating incident's `ReportPayload`. Always-in-DOM
modal shell, glass surfaces, `<.button>` variants, color reserved for the
severity indicator and the auto-hidden note. No console aesthetic, no chip palette.

1. **Step 1 — "What happened".** A short friendly explanation + the four promises
   (*you'll see exactly what gets sent · you can edit or remove anything · only
   the core dev team can see it, never public · nothing sends without your OK*),
   and an **optional** narrative textarea ("In your own words, what happened?").
2. **Step 2 — "What we'll attach".** The note ("we've already hidden paths, keys,
   IPs, emails — check for anything else personal and edit it out; this is exactly
   what will be sent"), then the **editable title** (single line) and **editable
   body** (textarea) pre-filled with the redacted report. The user scrubs freely.
3. **Step 3 — "Send".** Restate that it goes to a private inbox only the core dev
   team can read (not public); an explicit consent checkbox gates the primary
   **Send to the developer** button; a quiet **Copy instead** path renders the
   `{:fallback, bundle}` for manual copy. A "view exactly what will be sent"
   expander shows the assembled final text.

Back/Next navigation with a step indicator. (Working reference mockup:
`mockups/observability/consent-final-3step/index.html`.)

## Data flow & backend

Minimal change — split *building* a payload from *submitting* one:

- `ReportPayload.build/2` → `%{title, body, labels}` is unchanged; it produces the
  redacted default that pre-fills the step-2 fields.
- **New** `ErrorReports.submit_payload(payload, opts)` submits an *already-built
  (possibly edited)* payload via the configured `ReportTransport`, with the same
  `{:ok, url} | {:fallback, bundle}` semantics. `submit_report(bucket, opts)`
  becomes `build/2 |> submit_payload/2`.
- **Body assembly (pure, extracted, unit-tested):** `assemble_body(narrative,
  edited_body)` prepends a `## What happened (in the user's words)` section when
  the narrative is non-empty, otherwise returns the edited body unchanged.
- On Send, the modal builds `%{title: edited_title, body: assemble_body(narrative,
  edited_body), labels: …}` and submits via `submit_payload`. The `{:fallback,
  bundle}` text is that same assembled title + body.

The modal component owns its transient state (current step, narrative, edited
title, edited body, consent). Per ADR-030, any non-trivial render/assembly logic
is extracted to pure functions and unit-tested; the component stays thin wiring.

## Components & Storybook

The step panes become function components (typed attrs per MC0008), each with a
Storybook story per MC0009. Reuse `<.button>`, the always-in-DOM modal shell,
`<.badge>`, and glass surfaces.

## Out of scope (Milestone 2)

- Structured `%ReportSection{}` model, per-section/per-line removal, reassembly.
- The "your settings summary" section (the brainstorm's threat was in-text leaks,
  not config disclosure; addable later as plain text if ever wanted).
- Token/sensitive-span highlighting.
- The standalone `:user`-origin entry point and `Store` user-incident create path
  (Milestone 4).

## Testing

Test-first; no network in the suite.

- `assemble_body/2` — narrative present (leading section) vs absent (body
  unchanged); pure, `async: true`.
- `submit_payload/2` — `{:ok, url}` and `{:fallback, bundle}` via a stub
  transport (`opts[:transport]`); the fallback carries the *edited* text.
- Modal LiveView test — step navigation; fields pre-filled from the incident;
  Send disabled until consent; submitting sends the edited/assembled text (stub
  transport) and renders success vs fallback.
- Storybook compile/render for the new step components.

## Completion criteria

A user clicks "Report this" on a detected incident, optionally writes what
happened, reviews and edits the exact redacted text that will be sent, consents,
and the edited report is submitted via `submit_payload` (or presented as a
copyable bundle when no token is configured) — with no part of the report
leaving the machine before the consent step.
