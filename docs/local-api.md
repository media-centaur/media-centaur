# Local API

A JSON API for scripts and agents on this computer or your local network. Use it to find media, start downloads and follow them through to import. Downloads started through it are tracked and imported like any started in the app.

The complete contract is an OpenAPI 3.1 document. Give it to your agent or API client:

| Where | How |
|---|---|
| From your install | `GET /api/v1/openapi.json`, with your key. It always matches the running version. |
| Without an install | [`priv/api/openapi.json`](https://github.com/media-centaur/media-centaur/blob/main/priv/api/openapi.json) in the repository. |

## Set it up

1. Open Settings → Feature Flags and turn on **Local Downloads API**. It sits under **Downloads**. The row is listed while **Downloads** is on; the API is off whenever that is off. While it is off, every `/api` path answers 404.
2. Open Settings → Local Downloads API and press **Generate key**. Copy the key: it is shown once.
3. To reach the API from another device, set `bind = "0.0.0.0"` in the config file and restart the service. Settings → Local Downloads API lists the addresses to use.

Send the key on every request, including requests from this computer:

```sh
export MC=http://127.0.0.1:2160/api/v1   # use the address from Settings
export MC_KEY=...                        # the key you generated
curl -H "Authorization: Bearer $MC_KEY" "$MC/status"
```

Requests use plain HTTP, so anyone who can capture traffic on your network can read the key. If a key is lost or exposed, replace it in Settings; the old key stops working.

`capabilities.acquisition` in the status response must be `true` before anything can be downloaded.

## Let Media Centaur choose the releases

Media Centaur matches releases to the exact title, leaves out what you have and what is already downloading, and applies your quality settings. With `"approval_policy": "automatic"` it downloads without a person when every wanted film or episode was found within your quality settings.

This script downloads a film from start to finish. It needs bash and `jq`.

```bash
# 1. Find the title; take its tmdb_id and media_type
curl -s -H "Authorization: Bearer $MC_KEY" -G "$MC/titles" --data-urlencode "q=Sample Movie 2010" | jq '.titles[0]'

# 2. Plan it, with automatic approval; keep the plan's id
PLAN_ID=$(curl -s -H "Authorization: Bearer $MC_KEY" -H "Content-Type: application/json" "$MC/plans" \
  -d '{"tmdb_id": 12345, "media_type": "movie", "approval_policy": "automatic"}' | jq -r .id)

# 3. Wait for the plan to commit, or to stop for a person
while :; do
  PLAN=$(curl -s -H "Authorization: Bearer $MC_KEY" "$MC/plans/$PLAN_ID")
  case "$(jq -r '"\(.status) \(.awaiting_approval)"' <<<"$PLAN")" in
    "committed "* | "discarded "* | "ready true") break ;;
  esac
  sleep 10
done

# 4. If it committed, follow the download until it is in the library or has given up
PURSUIT_ID=$(jq -r .pursuit_id <<<"$PLAN")
until [ "$(curl -s -H "Authorization: Bearer $MC_KEY" "$MC/pursuits/$PURSUIT_ID" | jq -r .state)" != active ]; do sleep 60; done
```

For a series, send `"media_type": "tv"` and either a `scope` or `episodes`:

| Field | Plans |
|---|---|
| `"scope": "first_missing_season"` (default) | The lowest season with an aired episode you do not have. |
| `"scope": "latest_season"` | The newest season's aired episodes you do not have. |
| `"scope": "everything"` | Every aired episode you do not have. |
| `"episodes": [{"season": 2}, {"season": 3, "episode": 5}]` | Those seasons and episodes, where aired and missing. |

Episodes that new-episode grabbing already covers are left out too. `approval_policy` defaults to `review`, which always waits for an approve.

| Plan state | What to do |
|---|---|
| `status: committed` | Follow `pursuit_id`. |
| `status: ready`, `awaiting_approval: true` | Someone decides. Each unit's `gap` says why it has no release, and `error` why an automatic plan did not commit (it then reads `approval_policy: review`). `POST /plans/{id}/approve` commits the units that were found; `POST /plans/{id}/discard` drops the plan. |
| `status: ready`, `awaiting_approval: false` | The commit is in progress. Poll again. |

| Unit `gap` | Meaning | Move |
|---|---|---|
| `below_quality` | Only releases below your quality settings exist. | `POST /plans/{id}/accept-lower-quality` accepts them for this title from now on and searches again. |
| `pack_offered` | Only a larger pack contains it. | Take the pack in the app, or approve without it. |
| `not_found` | Nothing suitable was found. | Approve without it, or try again later. |
| `excluded` | Left out of the plan. | None. |
| `searching` | The search is still running. | Poll again. |
| `status: discarded` | Nothing will download. |

`POST /plans` answers 409 `already_downloading` when the film, or every episode in the scope, is already being downloaded or has an open plan, so a script can retry it safely. `GET /titles/{media_type}/{tmdb_id}` (`movie` or `tv`) then names the open plans and pursuits to follow, and says whether the library has the title. It answers 422 `nothing_to_plan` when the library has the film or nothing in the scope has aired. Episodes already being downloaded are left out of a series plan.

## Grab new releases as they come out

`PUT /titles/{media_type}/{tmdb_id}/auto-grab` turns on Auto-grab: Media Centaur plans the title's releases from now on, a series' new episodes as they air and a film when it is released. The title goes on the Watchlist at Grab. A series starts caught up on its latest aired episode, so nothing already aired is downloaded; plan those with `POST /plans`. `DELETE` on the same path turns it off and leaves the title on the Watchlist at Follow.

Whether those plans download at once or wait for an approve follows Settings → Acquisition → Download button: *Auto-select best release* downloads at once. Changes made through the API are not shared with friends.

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
| `GET /pursuits/{id}/alternatives` | Searches for releases the pursuit has not tried, at most 8. |
| `POST /pursuits/{id}/alternatives` | Downloads the release whose `guid` you send in place of the current one. |
| `POST /pursuits/{id}/search-again` | Plans what did not land, for pursuits started from a title. Takes `approval_policy`. |
| `GET /queue` | Everything in the download clients. |
| `DELETE /queue/{id}` | Removes an item and its files from its client. |

A pursuit with `awaiting_decision: true` needs another release: list them with `GET /pursuits/{id}/alternatives` and send the chosen `guid` to the same path. `available_actions` names what can be done now: `cancel`, `choose_release` or `search_again`. `units_satisfied` of `units_wanted` have landed in the library.

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
| 409 | `already_downloading` | It is already being downloaded or planned. |
| 409 | `not_cancellable` | The pursuit is already over. |
| 422 | `invalid_query` | The query's braces are malformed. |
| 422 | `nothing_to_plan` | You have it, or nothing in the scope has aired. |
| 422 | `nothing_to_grab` | The plan found no release. |
| 502 | `upstream_error` | TMDB did not answer. |
| 500 | `internal_server_error` | An unexpected failure, such as a download client refusing a removal. The app's console has the detail. |
| 503 | `not_configured` | Prowlarr or TMDB is not set up. See `GET /status`. |

`POST /grabs` is not idempotent: repeating it starts another download.
