---
status: planning
started: 2026-10-23
last_updated: 2026-10-23
---
# The TV app on Google Play

## Goal

Put the TV app on Google Play so that installing it on a TV is a Play
Store install: first the internal testing track for the owner's own
TV, then the production listing for anyone. Today the app is a signed
APK on a GitHub release that a user sideloads over adb or from a USB
stick (`remote-players.md`, M7). Opened 2026-10-23 at the owner's
direction as a campaign of its own, split from `remote-players.md`,
and parked until that campaign's remaining items and the owner's own
usability pass through the app are done.

## Glossary

Defined before use; refined as the campaign proceeds.

| Term | Meaning |
|---|---|
| **Play Console** | Google's developer account and publishing console: a one-time fee, an identity check, and either a **personal** or an **organization** account (the latter needs a D-U-N-S number). |
| **Internal testing track** | The Play track for up to 100 testers the developer names; no review, no listing. The first upload fixes the application id for good. |
| **Closed testing** | The track a personal account created after 2023-11-13 must run — 12 testers opted in for 14 continuous days — before it may apply for production access. Organization accounts are exempt. (Per Google's 2023 announcement; M1 confirms it against the Play Console help before the sit-down.) |
| **Production** | The public listing. Needs store assets, a content rating, a privacy policy and the data safety form; for TV also the Android TV review against Google's quality criteria. |
| **App bundle (AAB)** | The format Play requires for every upload; Play builds the APKs it serves from it. The GitHub release stays an APK. |
| **Play App Signing** | Play holds the app signing key and signs what it serves; the developer signs each upload with an **upload key**. The campaign keystore (`release.jks`) becomes the upload key. |
| **Upload automation** | The release workflow sending the AAB to a track through the Play Developer API with a service account, after the first upload, which the console requires by hand. |

## Status

Planning, parked. Nothing is done: the owner has no Play Console
account. Runs after `remote-players.md`'s remaining items and the
owner's usability pass, and before the merge of `remote-players` into
main and the major host release (the owner's sequence, 2026-10-23).

## Principles

1. The release is still the tag: a Play upload is derived from the tag
   by CI, as the APK is. Nothing is uploaded by hand after the first.
2. The GitHub release stays: a user without Play, or a TV without it,
   sideloads the same version.
3. The owner is at the keyboard for everything that touches the Play
   Console account: it is theirs to open and its identity is theirs.
   The agent prepares, researches and automates around it.

## Open decisions

1. **Personal or organization account.** A personal account created
   now must run closed testing with 12 testers for 14 continuous days
   before it can apply for production; an organization account is
   exempt but needs a D-U-N-S number, which can take up to 30 days to
   issue. Recommendation: confirm both rules in M1's research first;
   for a one-person project the closed-testing hurdle is the deciding
   fact — if it holds, an organization account for `media-centaur` is
   the shorter path to production, and the D-U-N-S request should go
   out at the start of M1 so the wait overlaps the rest.
2. **Upload automation.** Options: (a) Gradle Play Publisher (in
   maintenance mode; a plugin in the Gradle build); (b) one step in
   `release.yml` calling the Play Developer API with the service
   account's JSON as a repository secret. Recommendation: (b) — a
   workflow step beside the GitHub release, no build plugin.
3. **Who the internal testers are.** The owner's Google account alone,
   or a Google Group. Recommendation: the owner alone on the internal
   track; a group only if closed testing needs the twelve.

## Decisions made

* `2026-10-22` — Distribution through Google Play's internal testing track, so installing on the TV is a Play Store install with no public listing. (`remote-players.md`, conversation)
* `2026-10-23` — The TV app ships first as a signed APK built in CI and attached to a GitHub release; the Play track is set up with the owner at the keyboard after the automation lands. (`remote-players.md`, owner)
* `2026-10-23` — The application id is `app.mediacentaur.tv` and the display name "Media Centaur", for good. (`remote-players.md`, owner)
* `2026-10-23` — The Play work is its own campaign, split from `remote-players.md`; it runs after that campaign's remaining items and the owner's usability pass, and before the merge of `remote-players` and the major host release. (owner)

## Next steps

Milestones in order. Every milestone that changes an existing system
runs the campaign procedure (scope, research, decisions, `unify_design`
on the design, plan, `unify_design` on the plan, execution) and records
each step here.

1. **M1 — Research and the account.** Research, by the agent before
   the sit-down: Play's current account rules (fee, identity check,
   personal versus organization, the closed-testing rule and whom it
   binds); the internal track's limits; the TV listing requirements
   (the banner, `leanback` and `touchscreen` declarations — the
   manifest has them — "Android TV" in the description, at least one
   TV screenshot, the Android TV review after opting in under Setup →
   Advanced settings → Form factors); the 64-bit and 16 KB page-size
   requirement for TV apps in force since 2026-08-01 (the APK carries
   `arm64-v8a`; whether `dev.jdtech.mpv:libmpv` 1.0.0's native
   libraries are 16 KB-aligned is unverified — check with the SDK's
   alignment tool); Play App Signing's enrolment with an existing
   keystore as the upload key; the Play Developer API and service
   accounts. Each finding goes under Decisions made or Open decisions.
   Then the sit-down: the owner opens the account (decision 1),
   verifies identity, creates the app `app.mediacentaur.tv` /
   "Media Centaur", opts in to Android TV as a form factor, enrols in
   Play App Signing with the campaign keystore as the upload key.
2. **M2 — The bundle in the release.** `bundleRelease` beside
   `assembleRelease` in `release.yml`, signed by the same variables;
   the AAB attached to the GitHub release with its checksum; the
   version check unchanged. If libmpv fails the 16 KB alignment check,
   the fix (a newer artifact or a packaging change) lands here, with
   its own tag.
3. **M3 — The internal track.** The first upload by hand in the
   console; the service account and its secret; the upload step in
   `release.yml` (decision 2); the testers listed (decision 3); then a
   tag that lands on the internal track with no hand after the tag;
   the Sony installs the app from the Play Store, pairs and plays; the
   wiki's Android TV App page gains the Play install path beside the
   sideload.
4. **M4 — Production.** The store listing (TV banner, screenshots
   from the Sony, the description naming Android TV), the content
   rating, the privacy policy (the app talks to nothing but the user's
   own host — say so), the data safety form, closed testing if the
   account needs it, the Android TV review. Then the Pair card and the
   wiki page name the listing as the install path and the GitHub
   release as the alternative.

## Completion criteria

* A tag of `media-centaur-android` reaches the internal testing track
  with no hand after the tag, signed with the upload key.
* The Sony installs the TV app from the Play Store, pairs with the
  host and plays.
* The app is published on Google Play for Android TV; the Pair card
  and the wiki's Android TV App page name the listing as the install
  path and the GitHub release as the alternative.

## Pointers

* `~/src/media-centaur/android-app` — the TV app
  (`app/build.gradle.kts`: `appVersionName`, `signingConfigs.release`;
  `.github/workflows/release.yml`; the manifest's `leanback`,
  `touchscreen` and `banner` declarations), public at
  <https://github.com/media-centaur/media-centaur-android>.
* The keystore: `~/.config/media-centaur-android/release.jks`
  (PKCS12, alias `media-centaur-tv`), passwords in `release.env`
  beside it, archived through Fae (run `93d58c52`).
* Wiki `Android-TV-App.md` — the install section says the app is not
  on the Play Store yet.
* `remote-players.md`, the M7 record — the release path's design and
  execution.
* Google: internal testing
  <https://support.google.com/googleplay/android-developer/answer/9845334>;
  developer account verification
  <https://support.google.com/googleplay/android-developer/answer/10788890>;
  TV distribution
  <https://developer.android.com/training/tv/publishing/distribute>;
  TV checklist
  <https://developer.android.com/training/tv/publishing/checklist>.
* Upload: Gradle Play Publisher
  <https://github.com/Triple-T/gradle-play-publisher>; the Play
  Developer API (`androidpublisher`).
