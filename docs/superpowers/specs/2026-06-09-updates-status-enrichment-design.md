# Updates Status Enrichment — Design

**Date:** 2026-06-09
**Status:** Approved, executing

## Problem

The Updates (self_update) status tile is a wall of small text/links. Beautify it, and — like a system Software-Update screen — surface the **improvements each version brought**: "What's new" for the available update, and per-version notes inline-expandable in the history list.

## Persona & guardrails

Enthusiast persona (auto-memory `project-status-page-persona`): clearer hierarchy + the "what changed" narrative. **Reuse-first** (auto-memory `feedback-quality-bar`): a complete CHANGELOG-shaped markdown parser+renderer already exists — `MediaCentaurWeb.Live.SettingsLive.ReleaseNotes` (`parse/1` + `release_notes/1` component, used by Settings → Updates). Do not duplicate it.

## Design — reuse-first

### Net-new: `MediaCentaur.SelfUpdate.Changelog` (a splitter, not a parser)

- A pure `split/1` that takes changelog markdown and returns `[%{version, date, body}]`, splitting on `## vX.Y.Z — DATE` headers (em-dash `—`, U+2014); `body` is that version's raw markdown chunk (the `###`/entries between this header and the next), trimmed. Skips the file preamble before the first version header. Pure → unit-tested with a synthetic fixture.
- Compile-time embed: `@external_resource "CHANGELOG.md"` + `@raw File.read!("CHANGELOG.md")`; `all/0` = `split(@raw)`. `for_version/1` → that version's body markdown or `nil`. The running release carries its own per-version notes; no runtime file/network dependency.
- Exported from the SelfUpdate boundary (currently exports `[UpdateChecker]`).

### Reuse `ReleaseNotes` for all rendering

Feed it `latest_release.body` (available update) or a per-version `body` chunk (history). It already renders `### Improved` → uppercase label + bold-headline-plus-body paragraphs — exactly the "headlines + body" depth chosen.

### Beautified `self_update_widget`

- **Header**: `v{version}` + a status pill — `Up to date` (success) / `Update available · v{tag}` (info) — via the existing `SystemSection.update_status_{tone,label}`.
- **"What's new" block** (only when `status == :update_available`): `<ReleaseNotes.release_notes body={@latest_release.body} />`. Reuses the Settings component on the status hub (the surface the user asked to put it on).
- **History (recent 5)**: each entry a native `<details>`/`<summary>` disclosure (Activity widgets are stateless pure renders — no LiveView state, native HTML disclosure). Collapsed: `v{version} · {date}`. Expanded: `<ReleaseNotes.release_notes body={entry.notes_body} />`. Entries with `notes_body == nil` render a plain row (no disclosure).
- **Settings** (schedule + auto-install) and **apply progress**: kept, compacted.

### StatusLive wiring (minimal)

In `assign_self_update/1`, enrich history: `SelfUpdate.upgrade_history() |> Enum.take(5) |> Enum.map(&Map.put(&1, :notes_body, Changelog.for_version(&1.version)))`. Everything else (`version`, `status`, `latest_release`, schedule flags, apply phase) already flows through `activity_bundle/1`.

## What this is NOT

- No new markdown parser/renderer — `ReleaseNotes` is reused.
- No runtime CHANGELOG file read or per-version GitHub fetch — installed versions come from the compile-time embed; the available (newer-than-build) update uses the already-fetched `latest_release.body`.
- No LiveView interaction state — inline expand is native `<details>`.

## Testing

- `Changelog.split/1` — unit test with a synthetic 2–3 version fixture: correct version/date extraction, body chunking, preamble skip, off-format degradation (never crash). Plus a smoke test that `all/0` is non-empty and `for_version(current_version)` is non-nil (the real embedded file).
- Widget render — storybook variations (MC0009): up-to-date, update-available (with `latest_release.body`), history with expandable notes, history entry without notes.
- StatusLive wiring — the existing self_update tests stay green; add an assertion that the `?subsystem=self_update` drill-in renders a history `<details>` / version when history has notes.

## Files

- New: `lib/media_centaur/self_update/changelog.ex` (+ test).
- Modify: `lib/media_centaur/self_update.ex` (export `Changelog`).
- Modify: `lib/media_centaur_web/components/activity_widget_components.ex` (`self_update_widget/1` rework; use `ReleaseNotes`).
- Modify: `lib/media_centaur_web/live/status_live.ex` (`assign_self_update/1` enrich + alias).
- Modify: `storybook/status/self_update_widget.story.exs` (variations).
- Modify: `test/media_centaur_web/live/status_live_test.exs` (wiring assertion).

## Open items for planning

- Confirm `ReleaseNotes` renders acceptably inside a `<details>` (it's plain blocks; should be fine).
- Confirm `SelfUpdate.upgrade_history/0` entry shape is `%{version, recorded_at}` (verified) for the `Map.put(:notes_body, …)` enrich.
