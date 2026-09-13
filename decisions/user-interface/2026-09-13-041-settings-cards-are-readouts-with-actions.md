---
status: accepted
date: 2026-09-13
---
# Settings cards are readouts with actions, from one kit

Enacts the design in
[`docs/superpowers/specs/2026-09-13-settings-readout-kit-design.md`](../../docs/superpowers/specs/2026-09-13-settings-readout-kit-design.md).
Replaces decision 11 of the download-button default-action spec (a native
select on a "Download button" card). Takes UIDR-034's stance (a surface with
nothing on it states why) for gated settings cards.

## Context and Problem Statement

Settings carried two visual idioms on one page. Form cards (an `h2`, Save
at the top right, uppercase field labels, monospace inputs, a footer with a
test) for Prowlarr, both download clients, TMDB, Media Import, Playback and
Language; readout cards (an uppercase title, one explanatory line, rows that
save on the act, disclosures for rare actions) for Social, Library,
Preferences and Services; a third idiom on System and a fourth on Controls.
Acquisition showed five forms and five Save buttons for values entered once,
and buried the state a person returns for (which client, where, connected,
since when) under blank password inputs. The integration form skeleton
existed four times, the field markup about twenty, readiness was drawn four
ways, and the kit had no stories because it lived outside the components
tree.

## Decision Outcome

1. **The readout is the resting state.** An external connection (TMDB,
   Prowlarr, each download client, each relay) is one **connection row**:
   state dot, name, address as a link to its web UI, credential presence in
   words, state word with the test's age, and its actions. The form appears
   only when Edit or Set up is pressed, beneath the row, one at a time, with
   Cancel, Save and test, and Save at its foot. Test on the readout re-tests
   the saved values without opening the form.
2. **Save on the act is the page's default.** Booleans are toggle rows,
   bounded numbers are stepper rows over a fixed ladder, enums of four or
   fewer are choice rows on the house segmented pill, larger enums are
   select rows, free text commits on Enter or blur, lists are rows plus an
   inline add. A Save button exists only inside a connection row's edit
   form.
3. **One structure for every section.** The shell renders the section's
   title and one-line description; section modules render cards only; every
   card is `settings_card` (uppercase title, optional description, optional
   action, rows). No section-local heading dialects.
4. **A gated card stays and says what it needs.** Download button and
   Auto-acquisition render their title and "Available once Prowlarr's
   connection test passes." while Prowlarr is not ready, instead of
   vanishing.
5. **One kit, in the components tree, with stories.**
   `MediaCentaurWeb.Components.Settings` under
   `lib/media_centaur_web/components/settings/`, each component with a story
   under `storybook/settings/`, so MC0009 pins its contracts.
   `MediaCentaurWeb.SettingsLive.Components` retires.
6. **The automatic quality policy is two choices**, highest resolution and
   within-resolution preference. The configurable floor and the 4K patience
   window are removed (owner decision, 2026-09-13); the automatic floor is
   1080p, below it is the per-title acceptance of ADR-063 §2.
7. **One owner of connection state.** `MediaCentaur.IntegrationHealth`
   tracks the four `Capabilities` subjects, runs every connection test,
   persists an explicit verify's result for readiness, seeds from the
   persisted test at boot and probes nothing on its own. Settings, the
   setup tour and any later surface test through `verify/1` and render
   from its status; Settings keeps no private test machinery. (Added by
   the unify_design pass the same day; spec D22–D28.)

### Consequences

* Good, because a configured install's Acquisition section reads in one
  glance: three rows, three states, and the two policies beneath.
* Good, because readiness has one drawing on Settings, in the vocabulary
  `Capabilities` already persists.
* Good, because the kit is pinned by stories and Credo instead of by
  convention.
* Good, because a person who has not set up Prowlarr learns that a Download
  button and Auto-acquisition exist and what they wait on.
* Bad, because editing a credential is one click further away than an
  always-open form.
* Bad, because a tracked episode grabbed at 1080p stays at 1080p when its
  4K lands later; nothing upgrades today, and the window that used to hold
  out for 4K is gone.
* Bad, because the change touches every section and its tests in one
  campaign rather than one section at a time.
* Good, because a verify from the setup tour now makes the install
  ready; before, only Settings' own test persisted.
* Bad, because there are no boot-time probes: an integration that is
  down at boot reads as it last tested until someone tests it.

## Anti-patterns this record names

* **The form as the resting state** for values entered once.
* **Save in the header**, above the fields it saves.
* **The one-option select** (a slot's type select whose only real choice is
  the one shown).
* **Vanishing gated features** that hide instead of stating their
  prerequisite.
* **Three ways to add an entry.** A list setting is rows plus an inline
  input and Add; the media-directory dialog is the one exception because its
  entry has three fields.
