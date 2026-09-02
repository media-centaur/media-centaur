# Friends Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** User-facing documentation for friends and recommendations — a wiki page, the settings and troubleshooting references, the FAQ entry on privacy, and the release-notes draft the next `/ship` uses — plus the contributor docs that describe the new contexts.

**Architecture:** The wiki (`~/src/media-centaur/media-centaur.wiki`, a sibling git repo) gets one new page, *Friends and Recommendations*, in the reference register (numbered setup steps, a table of what each block does, a table of statuses), and edits to *Settings-Reference*, *Troubleshooting*, *FAQ*, *_Sidebar*, and *Watchlist*. The app repo gets `docs/friends.md` (contributor deep-dive: contexts, topics, event shape, sync, test doubles) linked from `CLAUDE.md`'s docs map and `docs/architecture.md`, and the campaign file carries the *Migration safety* and *New* bullets for the changelog.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — Completion criteria ("Wiki + Settings docs updated for key management and relay setup"), build order layer 8. Copy in the house voice (`writing-copy` skill: reference register — steps, tables, complete; "entry" not "entity"; no "simply").

**Preconditions:** layers 1–7 on disk (`/discovery` Feed, `/discovery/watchlist`, `/discovery/friends` with identity, relays, roster blocks; the Recommend control on detail pages and watchlist rows; the Status Friends tile). Read the live copy from the components before writing — the wiki must match what renders: `lib/media_centaur_web/live/discovery_live/*.ex`, `lib/media_centaur_web/components/status_widgets/friends.ex`, `lib/media_centaur_web/components/detail/view_controls.ex`.

**House rules:** wiki commits with `git` in the wiki repo, message `wiki: <summary>`, no push; app commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag; no real titles in examples ("Sample Movie"); never paste a real npub/nsec — use `npub1…` / `nsec1…` placeholders.

---

### Task 1: Wiki — *Friends and Recommendations*

- [ ] **Step 1: Write `Friends-and-Recommendations.md`** in the wiki repo with these sections, reference register:

```
# Friends and Recommendations

Recommend a title to your friends, and read what they recommend to you — through Nostr relays, with no account and no server run by us. Everything is on the **Discovery** page: the **Feed** (what friends sent), the **Watchlist** (what you saved), and **Friends** (your key, your relays, your friends).

Discovery is an early preview. Turn on **Discovery** under [Settings → Preferences](Settings-Reference#preferences) to show it in the sidebar; the pages stay reachable by URL either way.

## How it works

- Your install has one **identity**: a key pair. The public half is your **npub** — what friends add. The private half is your **secret key** (`nsec1…`) — never share it; anyone who has it can publish as you.
- A **relay** is a server that stores and forwards signed messages. You choose which relays to use. Your group's own relay first (see [running a relay](#running-a-relay)); public relays are more entries.
- A **friend** is a public key you follow, with a name you choose. You only read recommendations from keys on your list, and only from the relays you configured.
- A **recommendation** is one signed message: the title plus an optional note. Recommending the same title again replaces the earlier message.

Your recommendations are visible to anyone who can read the relays you publish to. On a private allowlist relay that is your group; on a public relay that is everyone.

## Setup

1. Turn on **Discovery** under Settings → Preferences.
2. Open **Discovery → Friends**. Your key is created the first time you open the tab. Press **Copy** next to your npub and give it to your friends.
3. Under **Relays**, add your group's relay address (`wss://…`) and press **Add relay**. The row shows **Connected** when the relay accepts you.
4. Under **Friends**, paste a friend's npub, give them a name, and press **Add friend**.

Ask your friends to add your npub the same way, on the same relay.

## Recommending a title

| From | How |
|---|---|
| A movie or series page | Press the **Recommend** control next to the bookmark, add a note if you like, press **Send** |
| A watchlist row | Press **Recommend** on the row |

If no relay is connected, the recommendation is saved and sent when one connects.

## Reading recommendations

**Discovery → Feed** lists what your friends recommended, newest first, with who sent it and their note. Each row offers one action: **Add to watchlist**, or **In library** when you already have the title. Titles added from the feed keep who recommended them on the watchlist row.

## Relay status

| Status | Meaning |
|---|---|
| **Connected** | The relay accepted the connection and, if it requires it, your key |
| **Connecting** | Trying to reach it; retries back off up to a minute |
| **Not connected** | Unreachable right now; the row shows the last error |
| **Rejected** | The relay refused your key — on an allowlist relay, ask the operator to add your npub |

The [Status page](Status-Page) has a **Friends** tile with the same information as a summary.

## Moving or backing up your identity

Under **Friends → Secret key**, **Show secret key** reveals your `nsec1…`. Keep it somewhere safe; it is the only way to keep the same identity on another machine. To move: on the new machine, open the same disclosure, paste the key under **Import a secret key**, press **Replace identity** twice. Friends do not need to re-add you.

## Running a relay

A private relay with an allowlist keeps your group's recommendations between you. Setup lives in its own repository: [media-centaur/nostr-relay](https://github.com/media-centaur/nostr-relay) *(coming soon — until it exists, any Nostr relay that supports client authentication (NIP-42) with a pubkey allowlist works; `strfry` and `khatru` both do).*
```

Adjust every label to the rendered copy (read the components). Replace `Status-Page` with the wiki's real page name for `/status` (`ls ~/src/media-centaur/media-centaur.wiki`), and the relay repository link with whatever the owner has named in the campaign file — if no repo exists yet, keep the "coming soon" sentence and no dead link.

- [ ] **Step 2: Cross-links** — `_Sidebar.md`: add **Friends and Recommendations** under the *Using Media Centaur* group next to Watchlist; `Watchlist.md`: first paragraph mentions the Feed as the other Discovery tab and links the new page; `Home.md` line listing "browsing, watchlist, …" adds "friends' recommendations".

- [ ] **Step 3: Settings-Reference** — the **Discovery** bullet: extend with "and the Friends tab (your key, relays, friends)". No new settings rows (identity, relays, friends live on the Friends tab, not in Settings).

- [ ] **Step 4: Troubleshooting** — add a section *Friends and relays* with three entries in the page's existing format: **A relay shows Rejected** (allowlist; give the operator your npub); **A relay stays Not connected** (address must start with `wss://` or `ws://`; check the last error on the row; firewalls); **A friend's recommendations do not appear** (both on the same relay; their npub added on your side; check the Feed tab, not the watchlist).

- [ ] **Step 5: FAQ** — one entry: **Who can see my recommendations?** — anyone who can read the relays you publish to; a private allowlist relay keeps it to your group; nothing is sent until you add a relay.

- [ ] **Step 6:** Commit the wiki: `wiki: Friends and Recommendations page; settings, troubleshooting, FAQ entries`. No push.

---

### Task 2: Contributor docs

- [ ] `docs/friends.md`: contexts (`Nostr` protocol lib, `Friends` network config, `Recommendations` content, `Discovery` unaware of both), topics (`friends:updates`, `friends:connections`, `recommendations:updates`) with their message shapes, the event shape (kind 32160, address tag, content), the sync algorithm (per-relay feed + own-events diff after EOSE), the connection state machine and backoff, NIP-42 flow, the test doubles (`FakeRelay`), the gates (`:start_relay_connections`, `:start_recommendations_sync`), the secret's storage (sensitive config key), the `decimal` override rationale, and the scheduled migrations (flat watchlist columns drop). Pointers to moduledocs rather than repetition. Link it from `CLAUDE.md`'s "Other domains" row and from `docs/architecture.md` where the contexts table already lists `Nostr`, `Friends`, `Discovery` (add `Recommendations` if missing).
- [ ] Commit `docs: friends and recommendations contributor guide`.

---

### Task 3: Release notes draft + campaign

- [ ] `campaigns/friends-recommendations.md`, the existing "CHANGELOG at the next /ship" item: extend with the *New* bullets in the changelog's voice: **Recommend titles to friends and read what they recommend.** Discovery page with Feed, Watchlist and Friends tabs; your key, your relays, your friends; recommendations travel over Nostr relays you choose, with no account and no server we run. Early preview behind the Discovery preference. **Watchlist is now a tab of Discovery** (`/discovery/watchlist`); the Discovery preference replaces the Watchlist preference. *Migration safety*: watchlist entries store their title as one value (converted automatically); new `relays`, `friends`, `recommendations` tables; the `show_watchlist` preference row is renamed. Also note the new dependency footprint (pure Elixir, no native code).
- [ ] Status: "Layer 8 (docs) landed; next: owner review of the full campaign, then layer 9 (hardening) after iteration."
- [ ] Commit `docs(campaign): documentation landed; ready for owner review`.

---

## Self-review

**Spec coverage:** Completion criteria "Wiki + Settings docs updated for key management and relay setup" → Task 1 (setup steps, secret key section, relay status table, Settings-Reference); Troubleshooting new failure modes and FAQ (CLAUDE.md wiki rules) → Task 1; contributor docs for new contexts → Task 2; changelog per the safe-migration rule → Task 3.

**Placeholders:** the relay repository link is deliberately conditional on the repo existing; the plan says what to write in either case.
