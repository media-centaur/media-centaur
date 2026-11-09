# Local API

A JSON API for scripts and agents on this computer or your local network. Use it to find media, start downloads and follow them through to import. Downloads started through it are tracked and imported like any started in the app.

The complete contract is an OpenAPI 3.1 document. Give it to your agent or API client:

| Where | How |
|---|---|
| From your install | `GET /api/v1/openapi.json`, with your key. It always matches the running version. |
| Without an install | [`priv/api/openapi.json`](https://github.com/media-centaur/media-centaur/blob/main/priv/api/openapi.json) in the repository. |

## Set it up

1. Open Settings → Feature Flags and turn on **Local API**. While it is off, every `/api` path answers 404.
2. Open Settings → Local API and press **Generate key**. Copy the key: it is shown once.
3. To reach the API from another device, set `bind = "0.0.0.0"` in the config file and restart the service. Settings → Local API lists the addresses to use.

Send the key on every request, including requests from this computer:

```sh
export MC=http://127.0.0.1:2160/api/v1   # use the address from Settings
export MC_KEY=...                        # the key you generated
curl -H "Authorization: Bearer $MC_KEY" "$MC/status"
```

Requests use plain HTTP, so anyone who can capture traffic on your network can read the key. If a key is lost or exposed, replace it in Settings; the old key stops working.

`capabilities.acquisition` in the status response must be `true` before anything can be downloaded.

## Let Media Centaur choose the releases

Media Centaur matches releases to the exact title, skips what you own and applies your quality settings.

```sh
# 1. Find the title
curl -H "Authorization: Bearer $MC_KEY" -G "$MC/titles" --data-urlencode "q=Sample Show"

# 2. Plan it. "automatic" commits without a person when the plan is clean.
curl -H "Authorization: Bearer $MC_KEY" -H "Content-Type: application/json" "$MC/plans" \
  -d '{"tmdb_id": 12345, "media_type": "tv", "approval_policy": "automatic", "scope": "latest_season"}'

# 3. Poll the plan until its status is no longer "planning"
curl -H "Authorization: Bearer $MC_KEY" "$MC/plans/$PLAN_ID"
```

| Plan state | What to do |
|---|---|
| `status: committed` | Follow `pursuit_id`. |
| `status: ready`, `awaiting_approval: true` | Read `units`, then `POST /plans/{id}/approve` or `POST /plans/{id}/discard`. An automatic plan stops here unless every wanted unit was found within your quality settings. |
| `status: ready`, `awaiting_approval: false` | The commit is in progress. Poll again. |
| `status: discarded` | Nothing will download. |

`approval_policy` defaults to `review`, which always waits for an approve. `scope` applies to series: `first_missing_season` (default), `latest_season` or `everything`.

## Choose the release yourself

```sh
# 1. Search. Braces expand to one search per term.
curl -H "Authorization: Bearer $MC_KEY" -G "$MC/releases" --data-urlencode "q=Sample Show S01E{01-02}"

# 2. Grab, sending back the q you searched and each release's guid and term
curl -H "Authorization: Bearer $MC_KEY" -H "Content-Type: application/json" "$MC/grabs" \
  -d '{"query": "Sample Show S01E{01-02}", "releases": [{"guid": "...", "term": "Sample Show S01E01"}]}'
```

A term with `status: "failed"` is an indexer failure, not an absence of releases. Results are reused for 30 minutes; add `refresh=true` to search again.

## Follow and control downloads

| Request | Effect |
|---|---|
| `GET /pursuits` | Downloads in flight. `?state=failed`, `cancelled`, `succeeded` or `terminal` lists finished ones; `?limit=` caps the list (default 50, at most 200). |
| `GET /pursuits/{id}` | Progress. `state` of `satisfied`, `partial`, `exhausted` or `cancelled` is final. |
| `POST /pursuits/{id}/cancel` | Stops the download and removes its partial data. |
| `POST /pursuits/{id}/search-again` | Plans what did not land, for pursuits started from a title. Takes `approval_policy`. |
| `GET /queue` | Everything in the download clients. |
| `DELETE /queue/{id}` | Removes an item and its files from its client. |

A pursuit with `awaiting_decision: true` needs a person to pick an alternative in the app.

## Errors

Every failure has the same body. Branch on `code`:

```json
{"error": {"code": "plan_not_ready", "message": "The plan is not in a state that allows this."}}
```

| Status | `code` | Meaning |
|---|---|---|
| 400 | `invalid_request` | A parameter is missing or invalid; `message` says which. |
| 401 | `unauthorized` | The key is missing or wrong. |
| 404 | `not_found` | No such resource, or the feature is off. |
| 404 | `release_unavailable` | No search recorded that guid. Search again. |
| 409 | `plan_not_ready` | The plan's status does not allow this. |
| 409 | `already_downloading` | Part of the plan is already being downloaded. |
| 409 | `not_cancellable` | The pursuit is already over. |
| 422 | `invalid_query` | The query's braces are malformed. |
| 422 | `nothing_to_plan` | Nothing is left to download for this. |
| 422 | `nothing_to_grab` | The plan found no release. |
| 502 | `upstream_error` | TMDB did not answer. |
| 503 | `not_configured` | Prowlarr or TMDB is not set up. See `GET /status`. |

`POST /grabs` and `POST /plans` are not idempotent: repeating one starts another download or plan.
