---
status: accepted
date: 2026-11-09
---
# The Local API is admitted by its key

## Context and Problem Statement

Scripts and agents on the local network need to search and start downloads through the app. The gate (`Plugs.RemoteAccess`) admits loopback requests as the host and LAN requests holding a paired player's session. A script has no session. Loopback trust is also unsafe for an API that starts downloads: a web page in the host's browser can send a request to 127.0.0.1 under an IP-literal `Host`, which the gate accepts.

## Decision Outcome

The Local API, under `/api`, is a feature (ADR-081, `:local_api`, default off) with its own admission, `Plugs.LocalApi`, and the gate leaves `/api` to it.

1. While the flag is off, every `/api` path answers 404.
2. While it is on, every request carries `Authorization: Bearer <key>`, from loopback too. There is no trusted address.
3. There is one key. The app generates it, stores only its SHA-256 digest in Settings, and shows it once. Generating again replaces it.
4. The API is served over plain HTTP, like the rest of the app. The key is readable by anyone able to capture local network traffic; the Settings section says so.

### Consequences

* Good, because a browser page and a rebound domain have no key to send, so no `Origin` or content-type rules are needed.
* Good, because a database or backup does not contain a usable key.
* Bad, because a lost key must be replaced, and every caller then needs the new one.
* Bad, because one key cannot tell callers apart or be revoked for one of them.
