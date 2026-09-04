# Social protocol

Every message Media Centaur puts on a Nostr relay: its kind number, the rule a relay stores it by, its tags and content fields, and the rules the app and the relay follow when reading, replacing and deleting. This page is the contract between the app and any relay it talks to, including [social-relay](https://github.com/media-centaur/social-relay).

The canonical copy is `docs/social-protocol.md` in the app repository; the wiki page is generated from it. Change the file, not the wiki.

## Kind numbers

A kind is a message's type identifier. Its number also fixes how relays store it, because the protocol assigns one storage rule per range:

| Range | Rule | A relay keeps |
|---|---|---|
| 1000–9999 | Regular | every message |
| 10000–19999 | Replaceable | the latest per signer per kind |
| 20000–29999 | Ephemeral | nothing; forwarded to connected clients only |
| 30000–39999 | Addressable | the latest per signer per kind per `d` tag |

Media Centaur's kinds occupy the same block in each range: **2160–2999**, **12160–12999**, **22160–22999**, **32160–32999**. A new kind takes the next free number in the block of the range whose rule fits, after a check against the [public kind registry](https://github.com/nostr-protocol/nips#event-kinds). Numbers are never reused, retired ones included. A kind exists when it has a row below.

| Kind | Name | Rule | Defined by |
|---|---|---|---|
| 32160 | Recommendation | Addressable | Media Centaur |
| 5 | Deletion | Regular | Nostr (NIP-09) |
| 22242 | Relay authentication | Ephemeral | Nostr (NIP-42) |
| 27235 | HTTP authentication, used by relay administration | Ephemeral | Nostr (NIP-98) |

## Envelope

Every message is a NIP-01 event: `id`, `pubkey`, `created_at` (Unix seconds), `kind`, `tags`, `content`, `sig`. Media Centaur signs with the install's identity key (secp256k1, BIP-340 Schnorr). Readers verify the signature and drop anything that fails, and drop anything from a signer they do not follow.

## Recommendation (kind 32160)

One person recommending one title. The address is the title, so a person holds at most one recommendation per title; recommending it again replaces the earlier one everywhere.

**Tags**

| Tag | Value | Required |
|---|---|---|
| `d` | `tmdb:<media_type>:<tmdb_id>` — `media_type` is `movie` or `tv_series`, `tmdb_id` a positive integer. Example: `tmdb:movie:603`. | yes |
| `p` | Recipient public key, for a directed recommendation. Reserved; never set today. | no |

**Content** is a JSON object:

| Field | Type | Cap | Notes |
|---|---|---|---|
| `v` | integer | | Content schema version. Absent means 1. |
| `title` | object | | Snapshot of the title, below. |
| `note` | string or null | 500 characters | The sender's note. |
| `recommended_at` | integer, Unix seconds | | When the person recommended the title. Absent means `created_at`. |

`title`:

| Field | Type | Cap | Required |
|---|---|---|---|
| `tmdb_id` | integer | | yes; must equal the `d` tag |
| `media_type` | `"movie"` or `"tv_series"` | | yes; must equal the `d` tag |
| `name` | string | 300 characters | yes |
| `year` | string | | no |
| `release_date` | `YYYY-MM-DD` | | no |
| `poster_path` | string, TMDB path | | no |
| `backdrop_path` | string, TMDB path | | no |
| `overview` | string | 2000 characters | no |

**Rules**

- Readers ignore fields they do not know, so fields can be added without a version bump. A change that alters the meaning of an existing field bumps `v`; readers drop a message whose `v` they do not understand.
- A message whose `d` tag and `title` disagree, whose content is not JSON, or whose strings exceed a cap is dropped as malformed. Nothing is repaired or truncated.
- Between two recommendations from the same signer for the same title, the newer `created_at` wins. On a tie, what is already stored is kept.
- `created_at` is the wire time and decides only which copy wins. `recommended_at` is when the person acted; readers order and display by it and never derive one from the other. The two coincide when a message is made and sent in one go.

## Deletion (kind 5)

A person withdrawing their own recommendation. Standard NIP-09, restricted to the address form.

**Tags**

| Tag | Value | Required |
|---|---|---|
| `a` | `32160:<signer pubkey>:tmdb:<media_type>:<tmdb_id>` — the address of the recommendation being withdrawn. One `a` tag per deletion. | yes |
| `e` | The id of the recommendation event, if known. | no |
| `deleted_at` | When the person withdrew it, Unix seconds. Absent means `created_at`. Same split as a recommendation's `recommended_at`: `created_at` decides, `deleted_at` is shown. | no |

`content` may carry a reason; readers ignore it.

**Rules**

1. A deletion applies only to the signer's own recommendation: the pubkey inside the `a` tag must equal the deletion's `pubkey`. A relay refuses anything else.
2. A deletion applies to a recommendation whose `created_at` is at or before the deletion's.
3. A relay that accepts a deletion removes the addressed recommendation and stores the deletion in its place. A signer's address therefore always holds exactly one record: a recommendation or a deletion. A relay never holds both, and never more than one of either.
4. A recommendation arriving at an address whose stored deletion is newer than the recommendation is refused. A recommendation newer than the stored deletion replaces it: the title is recommended again.
5. Readers keep a deletion as a tombstone on their copy of the recommendation. The recommendation is hidden, not removed, so a copy of it arriving later from another relay cannot bring it back. A newer recommendation for the same address revives it.
6. Deletions are kept as long as the address is deleted. Rule 3 bounds storage to one record per signer per title however many times a title is recommended and withdrawn.

## Reading and sync

The app keeps one long-lived connection per relay and, on every connect, opens two subscriptions:

| Subscription | Authors | Kinds | Purpose |
|---|---|---|---|
| `feed` | followed keys plus the install's own | 32160, 5 | what friends recommended and withdrew |
| `own:<relay url>` | the install's own | 32160, 5 | what this relay holds of ours |

**From the start, every time.** Every connect reads the relay's whole stored set for the subscription; the app keeps no `since` cursor. A relay holds one record per signer per title (Deletion rule 3), so a friend group's history is a page or two, and a cursor keyed on `created_at` would skip a message published late with an older stamp — a withdrawal made while offline. Re-reading is idempotent: a reader ignores anything not newer than what it holds.

**Paged.** The app asks for at most 500 events per request. A batch that comes back full is followed by another request with `until` set to the oldest `created_at` in the batch, until a batch comes back short.

**Own-events diff.** When the `own:<url>` subscription reaches end-of-stored-events, the app publishes to that relay every own recommendation and deletion the relay did not send. This is how a message made while offline, or before the relay was added, reaches it later.

**Roster changes.** Adding or removing a friend re-issues `feed` on every relay with the new author list.

## What a relay must do

For a relay to carry Media Centaur traffic:

| Requirement | Detail |
|---|---|
| Authentication | Challenge on connect (NIP-42). The app answers immediately and never reacts to an `auth-required:` rejection. |
| Access | Reads and writes gated by an allowlist of public keys. |
| Kinds stored | 32160 and 5, with the rules above. Every other kind refused with `blocked:`. |
| Addressable storage | One record per signer per address, recommendation or deletion (Deletion rule 3). |
| Deletion checks | Deletion rules 1, 2 and 4. |
| Filters | `authors`, `kinds`, `since`, `until`, `limit` (NIP-01). `limit` capped at 500. |
| End of stored events | `EOSE` after the stored matches of every `REQ`. |

**Rejection reasons.** Fixed strings; the app shows them on the relay row.

| Situation | Answer |
|---|---|
| `REQ` before authentication | `CLOSED <sub> auth-required: authenticate to read from this relay` |
| `EVENT` before authentication | `OK <id> false auth-required: authenticate to write to this relay` |
| Authenticated but not on the allowlist | `restricted: this key is not a member of this relay` on both |
| A member publishing another key's event | `OK <id> false restricted: the event author is not a member of this relay` |
| A kind the relay does not store | `OK <id> false blocked: kind <n> is not stored by this relay` |
| A deletion naming another signer's address | `OK <id> false blocked: only the author may delete an event` |
| A recommendation older than the stored deletion of its address | `OK <id> false blocked: a newer deletion exists for this address` |
| A deletion for an address the relay never held | `OK <id> true` — nothing to remove, still a valid statement |

## Changes

| Date | Change |
|---|---|
| 2026-09-02 | First version: kind blocks, Recommendation (32160) with content version `v`, Deletion (5), incremental and paged sync, relay requirements. |
| 2026-09-04 | Domain times: `recommended_at` in a recommendation's content, `deleted_at` tag on a deletion; `created_at` decides, the domain time is shown. Sync reads from the start on every connect; the `since` cursor is gone. Relay requirements unchanged. |
