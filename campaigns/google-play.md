---
status: in-progress
started: 2026-10-23
last_updated: 2026-10-25
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

M1's research done 2026-10-25 (record under M1 below). A personal
account (decided). BACK-to-home and the Menu-key dependency are built
on the host and in the TV app (unreleased; verified in tests, not yet
on the Sony); the banner artwork (open decision 6) is the owner's. Next:
the owner opens the account (the M1 sit-down).

## Principles

1. The release is still the tag: a Play upload is derived from the tag
   by CI, as the APK is. Nothing is uploaded by hand after the first.
2. The GitHub release stays: a user without Play, or a TV without it,
   sideloads the same version.
3. The owner is at the keyboard for everything that touches the Play
   Console account: it is theirs to open and its identity is theirs.
   The agent prepares, researches and automates around it.

## Open decisions

2. **Upload automation.** Options: (a) Gradle Play Publisher (in
   maintenance mode; a plugin in the Gradle build); (b) one step in
   `release.yml` calling the Play Developer API with the service
   account's JSON as a repository secret. Recommendation: (b) — a
   workflow step beside the GitHub release, no build plugin.
3. **Who the internal testers are.** The owner's Google account alone,
   or a Google Group. Recommendation: the owner alone on the internal
   track; a group only if closed testing needs the twelve.

6. **The banner names nothing (TV-BN, "the banner contains the app
   name").** `banner.xml` is a placeholder vector of two triangles.
   It needs real artwork with "Media Centaur" in it: the owner's call
   (the app's mark, 320×180, legible from the couch).

## Decisions made

* `2026-10-22` — Distribution through Google Play's internal testing track, so installing on the TV is a Play Store install with no public listing. (`remote-players.md`, conversation)
* `2026-10-23` — The TV app ships first as a signed APK built in CI and attached to a GitHub release; the Play track is set up with the owner at the keyboard after the automation lands. (`remote-players.md`, owner)
* `2026-10-23` — The application id is `app.mediacentaur.tv` and the display name "Media Centaur", for good. (`remote-players.md`, owner)
* `2026-10-23` — The Play work is its own campaign, split from `remote-players.md`; it runs after that campaign's remaining items and the owner's usability pass, and before the merge of `remote-players` and the major host release. (owner)
* `2026-10-25` — A **personal** Play Console account: closed testing (12 testers, 14 days) before production; the internal track is open at once. (owner; open decision 1 closed)
* `2026-10-25` — BACK with nothing left to peel leaves the app on the TV (TV-DB): host `cf99b381` (`leave_app`, UIDR-028 amended), TV app `5490789` (`MediaCentaurTV.leave()`, and the pairing page left on the first BACK). Ships with the next TV app release. (owner; open decision 4 closed)
* `2026-10-25` — The track menu without a Menu key (TV-DM): paused, the bar shows an Audio & subtitles button — DOWN reaches it, OK opens the menu, UP comes back; playing keeps every arrow a seek. Host `cf99b381`. (owner chose the paused button over DOWN-opens-the-menu and a full button row; open decision 5 closed)

## Next steps

Milestones in order. Every milestone that changes an existing system
runs the campaign procedure (scope, research, decisions, `unify_design`
on the design, plan, `unify_design` on the plan, execution) and records
each step here.

**M1 research, 2026-10-25** (Google's pages: Play Console Help
14151465, developer.android.com/docs/quality-guidelines/tv-app-quality):
* Closed testing — "personal developer accounts created after November
  13, 2023": 12 testers opted in continuously for 14 consecutive days
  (an opt-out restarts that tester's count), then production access is
  applied for on the Dashboard, reviewed in about seven days. The help
  page names no rule for organization accounts; third-party guides say
  they are exempt. Internal testing (up to 100 testers, no review) is
  open to either account at once — the owner's own TV needs nothing
  more, so decision 1 decides production's timeline, not M3's.
* Organization accounts need a D-U-N-S number (free, up to 30 business
  days; third-party sources). The one-time fee is USD 25.
* TV criteria (Tier 3, the review's bar): leanback launcher intent and
  touchscreen not required (the manifest has both); `minSdk` ≤ 31 (26);
  App Bundles mandatory (M2); at least one unaltered TV screenshot;
  from 2026-08-01 "TV apps must support both 32- and 64-bit
  architectures and comply with 16 KB page size requirements" — the
  APK carries armeabi-v7a, arm64-v8a, x86 and x86_64, and every native
  library, libmpv's included, is 16 KB-aligned in the zip and in its
  ELF segments (`mc-tv check-16k`, 2026-10-25). The 16 KB question is
  closed.
* D-pad and playback (TV-DP, TV-PC, TV-PP): five-way navigation,
  centre toggles pause, left/right seek, play/pause keys toggle — the
  viewing layer does all of it. TV-DB, TV-DM and TV-BN fail today:
  open decisions 4–6.
* Overscan (TV-OV, "no text or functionality is cut off by screen
  edges"): the sidebar's labels sit 24 px from the left edge of a
  1920 px page; unverified against the review, checked on a TV with
  overscan on before submitting.

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
   libraries are 16 KB-aligned was unverified — checked 2026-10-25,
   they are); Play App Signing's enrolment with an existing
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
