---
status: accepted
date: 2026-09-13
---
# Settings cards are readouts with actions, from one kit

Enacts the settings-readout-kit design (2026-09-13).

## Context and Problem Statement

Settings carried four visual idioms. Acquisition showed five forms and five Save buttons for values entered once and buried the state a person returns for under blank password inputs. The integration form existed four times.

## Decision Outcome

1. **The readout is the resting state.** An external connection (TMDB, Prowlarr, download clients, relays) is one connection row (`Components.Settings.ConnectionRow`): state dot, name, address, credential presence in words, state word with the test's age, actions. The form appears only on Edit or Set up, beneath the row; Test re-tests the saved values.
2. **Save on the act is the default**: toggle, stepper, choice (four or fewer), select, text on Enter or blur, list rows plus an inline add. A Save button exists only inside a connection row's edit form.
3. **One structure for every section**: every card is `settings_card`.
4. **A gated card stays and says what it needs** ("Available once Prowlarr's connection test passes.") (UIDR-034).
5. **One kit with stories**: `MediaCentaurWeb.Components.Settings`, pinned by MC0009.
6. **The automatic quality policy is two choices**, highest resolution and within-resolution preference (ADR-061). The configurable floor and the 4K patience window are removed (2026-09-13); the automatic floor is 1080p, below it the per-title acceptance of ADR-063.
7. **One owner of connection state.** `MediaCentaur.IntegrationHealth` runs every test through `verify/1`, persists the result as readiness, seeds from it at boot, probes nothing on its own; Settings and the setup tour render from its status.

### Consequences

* Editing a credential is one click further away. An integration down at boot reads as it last tested. A 1080p grab never upgrades to a later 4K.

## Anti-patterns

The form as the resting state; Save in the header; the one-option select; vanishing gated features; three ways to add an entry (rows plus inline Add; the media-directory dialog is the one exception).
