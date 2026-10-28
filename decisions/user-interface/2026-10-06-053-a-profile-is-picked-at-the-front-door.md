---
status: accepted
date: 2026-10-06
---
# A profile is picked at the front door and drawn as the identity tile

Design: `docs/superpowers/specs/2026-10-06-viewer-profiles-design.md`. Record: ADR-078.

## Context and Problem Statement

With more than one profile, the screen has to ask who is watching, and the answer has to be wrong as rarely as possible: a profile picked once and never asked again drifts onto the wrong person on a shared television. The app already has one way to draw a person — the identity tile (UIDR-047: the picture, else the letter) on the app's hue ring (UIDR-048) — and must not grow a second.

## Decision Outcome

Chosen option: a full-screen picker at session start, a switcher in the shell, one tile for every person.

1. **The picker is a session's front door.** `/profiles` asks "Who's watching?" over a row of large profile tiles with names, plus Add profile under the cap of eight. A session with no active profile lands there before any page. The session cookie has no expiry, so the question is asked on each launch of the app shell and never mid-session. *(Amended 2026-10-10: one surface, two situations. At the door — no active profile — it is full-screen, since there is no one to show in the shell and nowhere else to go. On a switch — an active profile exists — it is a page of the shell like Settings, the switcher entry lit, the sidebar the way out. It lives in `live_session :default` as the one view `ProfileAware` mounts without a profile instead of redirecting.)* *(Amended 2026-10-11: every place in the row is a tile. Add profile is the **add tile** — a dashed circle with a plus in the profile tile's column — and pressing it opens the name field in its place, with Add and Cancel; it began as a text field and button beside the tiles, the one thing in the row that was not a tile. A tile lifts under the pointer. On a switch the active profile's tile wears the chosen outline a hue swatch wears, with `aria-current`.)* *(Amended 2026-10-27: the tile grows to 128px, the identity tile's largest size and the one size it draws nowhere else — the picker is the one couch-distance moment it owns, not a utility list. The switch's "one surface, two situations" gained its other half: the door's dim atmosphere (`.page-side-dim-calm`) now wraps the in-shell switch too, which had none. Keyboard/gamepad focus on a tile draws on the identity tile's own circle instead of the generic rounded-rect button ring, so it reads as one shape with the "current profile" ring beside it rather than two nested rings of different geometry.)*
2. **With one profile there is no door.** No picker, no switcher, no change to any page, test or screenshot.
3. **The switcher is the first entry of the sidebar's System group**, present only with more than one profile; pressing it opens the picker inside the shell, with this entry current. It is drawn like the entries around it — a person icon and the profile's name — with the icon in the profile's hue as its one accent, and no picture. *(Amended 2026-10-09: it began as the profile's 32px identity tile above the Watch group, which gave the shared rail a permanent, saturated element for an action that is rarely taken; the owner asked for an entry that blends in. The identity tile still draws the person on the picker and in Settings.)* *(Amended 2026-10-27: activates on focus like every sidebar sibling — a gamepad arrowing onto it now just visits the picker, the same low-risk preview every other entry gives; switching a profile still needs a second, explicit SELECT on a tile within the page. Since the icon's hue is now this entry's whole color story most of the time it holds focus, the active wash and the keyboard/gamepad focus ring take the hue too, in place of the primary tint and primary ring every other System entry uses.)*
4. **One tile draws every person.** The identity tile's contract widens from a `Social.Person` to the three facts it draws — name, picture URL, hue — and the social surfaces pass them from their Person. A profile's name is required, so the person glyph never arises for one. *(Amended 2026-10-11: a profile's hue is required too, given at birth — the first palette hue no profile holds, in the swatch row's order — so the people of one install differ at a glance instead of all drawing at the primary's angle until someone visits Settings. The upgrade's owner profile keeps Blue, the angle it was drawn at; every other hueless profile takes the next free swatch. There is no "none" for a viewer profile; a friend without a published hue still draws at 250 by CSS.)*
5. **Profiles are edited in Settings → Profiles**, one kit card per profile (name, picture with the crop stage, colour, Remove profile as an arm gesture with "Their watching history goes with it."). Settings → Social's first card is relabelled **Social profile**.

### Consequences

* Good, because a person looks the same on the picker, in the shell, in Settings and on the Feed.
* Good, because a wrong-profile session lasts at most until the next launch.
* Bad, because at a desk the question is asked on every launch once a second profile exists; a sticky option is not offered until asked for.
* Bad, because the tile's story and its social callers are rewritten in the same change (MC0009).
