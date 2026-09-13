---
status: in-progress
started: 2026-09-13
last_updated: 2026-09-13
---
# Settings readout kit

## Goal

Every Settings section composes from one kit whose resting state is a
readout: an external connection is a row that shows what is configured
and how it is doing, its form appears only on Edit, and every other
setting saves the moment it changes. Acquisition gets the structural
redesign; the other twelve sections a mechanical restyle onto the same
kit. Alongside, the automatic quality policy loses its configurable
floor and its 4K patience window.

## Status

Phases A–D done 2026-09-13 (quality policy, kit + intros, one owner of
connection state, Acquisition + TMDB as connection rows), each behind a
green precommit; unpushed. Next: Phase E (Social), then F (the other
sections), then G (closure).

## Decisions made

* `2026-09-13` — Complete scope: all thirteen sections, not only Acquisition and Social. (owner)
* `2026-09-13` — The quality policy is two choices, highest resolution and within-resolution preference; the floor and the patience window go. Consequence accepted: a 1080p grab is not upgraded when 4K lands later. (owner; [UIDR-041](../decisions/user-interface/2026-09-13-041-settings-cards-are-readouts-with-actions.md) §6)
* `2026-09-13` — Live connectivity in the readout is not wanted; the row shows the persisted test. (owner)
* `2026-09-13` — unify_design pass: `IntegrationHealth` becomes the one owner of connection state (four ids, persists explicit verifies, seeds from the persisted test, no boot probes); Settings drops its private test machinery. Owner paid the cost. (spec D22–D33)
* `2026-09-13` — Inline edit expansion, not a dialog; the address is the Open link; Remove client lives in the edit form; Detect from Prowlarr sits on the Download clients card; gated cards stay and state their prerequisite. (spec D6–D17)

## Next steps

1. Phase A — quality policy simplification (backend, data migration, `AutoGrabSettings.put/2`). Ships with Phase D in the same release.
2. Phase B — the kit moves to the components tree with stories (incl. input, list, core Ladder); the shell renders section intros.
3. Phase C — one owner of connection state: `IntegrationHealth` four ids, per-slot verifier, persisted explicit verifies, seed from persisted; Settings' old forms test through it.
4. Phase D — Acquisition and TMDB on connection rows; tests; wiki.
5. Phase E — Social on the kit.
6. Phase F — the remaining sections, one commit each; retire the pre-kit helpers; wiki.
7. Phase G — glossary, skill, storybook notes; owner look; retire this file.

Plan: [`docs/superpowers/plans/2026-09-13-settings-readout-kit.md`](../docs/superpowers/plans/2026-09-13-settings-readout-kit.md).
Spec: [`docs/superpowers/specs/2026-09-13-settings-readout-kit-design.md`](../docs/superpowers/specs/2026-09-13-settings-readout-kit-design.md).

## Completion criteria

* Acquisition with every integration configured shows no input until Edit; each row shows name, address link, credential presence, state word and test age.
* `auto_grab.default_min_quality` and `auto_grab.4k_patience_hours` exist nowhere in `lib/`, the settings table, or the wiki; the data migration has run on the owner's install.
* Every section shows the shell's intro; no section module contains an `h2`; every card is `settings_card`; no card header carries a Save.
* Every kit component has a story; `mix precommit` passes.
* Settings-Reference and Release-Tracking on the wiki describe the rows as shipped.
* Owner has looked at Acquisition, Social and Media Import on the dev server.
