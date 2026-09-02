# Glossary

Contributor-facing definitions for terms with a precise project meaning.
User-facing vocabulary (entry vs entity, release) is governed by the
`writing-copy` skill and the guide-vocabulary rules; this file covers terms
as used in code, specs, and decision records.

| Term | Meaning |
|---|---|
| **App** | A launchable entry in the Apps launcher (`MediaCentaur.Apps.App`): name, one-line shell command, origin. User copy says "app"; code says `App`. |
| **Add-method** | A way of creating an App (the Steam picker, the manual form). Add-methods are importers that resolve to the uniform App shape at add time — launching never dispatches on them. |
| **Origin** | Provenance metadata an add-method records on an App (e.g. `%{"source" => "steam", "app_id" => 413150}`). Used for dedup and artwork refresh, never for launch behavior. |
| **Social** | The subsystem that connects one install to friends' installs over Nostr relays: identity, relays, friends, and the recommendations that travel between them. Bounded context `MediaCentaur.Social` (configuration) plus `MediaCentaur.Recommendations` (content) over `MediaCentaur.Nostr` (protocol). Status tile, incident component and console tag `:social`; the wire logs as `:nostr`. Its surfaces: the Settings **Social** section (identity, relays) and the Discovery **Friends** tab (roster). |
| **Friend** | One entry on the Social roster: a public key the user follows under a locally chosen nickname (`Social.Friend`, `friends` table). Friends are the only authors the feed accepts. **Friends** is also the roster feature's name: the Discovery tab at `/discovery/friends`. Never the name of the subsystem. |
| **Identity** | This install's secp256k1 keypair (`Social.Identity`), held as the sensitive `nostr_secret_key` config key. Shown as an **npub**, exported and imported as an **nsec**. |
| **Relay** | A Nostr WebSocket server the user has configured (`Social.Relay`, `relays` table). A **private relay** is one a friend group hosts with a pubkey allowlist (the `social-relay` repo); a **public relay** is anyone's. The app treats both identically. |
| **Connection** | The app's live WebSocket session to one relay (`Nostr.Connection`, one per URL, owned by `Social.Connections`). Its states are `connecting`, `connected`, `disconnected`, `auth_failed`; the relay block shows them as Connecting, Connected, Not connected, Rejected. |
| **Recommendation** | One signed kind-32160 event: a title snapshot from one author, with an optional note (`Recommendations.Recommendation`). Addressable, so recommending the same title again replaces the earlier event. Sent vs received is derived from the signature, never stored. |
| **Feed** | The Discovery tab listing recommendations from friends and from this install (marked "You"), newest first. Reading only; adding to the watchlist is the user's act. |
| **Discovery** | The page where titles come to the user: Feed, Watchlist and Friends tabs at `/discovery`, gated in the sidebar by the `show_discovery` preference. |
| **Title** | The app-wide TMDB title snapshot (`MediaCentaur.TMDB.Title`): identity (`tmdb_id`, `media_type`) plus render fields. Embedded in watchlist rows and recommendations. |
| **Addressable event** | A Nostr event kind in 30000–39999: relays keep only the newest event per (author, kind, `d` tag). Kind 32160 uses `d = tmdb:<media_type>:<tmdb_id>`. |
