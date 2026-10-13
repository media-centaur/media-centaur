# App-owned grabs — Implementation Plan

> **Withdrawn 2026-10-13.** Built in full on branch `app-owned-grabs`
> (plus one fix the review found), verified live against SABnzbd, and
> dropped unmerged on the owner's call: too much re-engineering of the
> grab path for a visual aim. Kept as history; see the design spec's
> amendment and `campaigns/download-phases.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app submits every grab to the download client itself and records the client's job id on the target at grab time, so a pursuit pairs with its job exactly from the first poll; Prowlarr is search only.

**Architecture:** `Acquisition.Grab` is the one grab path: it fetches the release payload through Prowlarr's download link (`Acquisition.ReleasePayload`), hands it to the protocol slot's driver through a new `DownloadClient.add/3` callback, and returns the job id (SABnzbd's `nzo_id`; qBittorrent's infohash, computed from the payload by `Downloads.InfoHash`). `Target.torrent_hash` becomes `download_id`. `QueueMatcher` pairs by id only; title containment retires. Hand-off availability (`{:handoff, slot}`) keeps its name and consumers; its writer and probe move from Prowlarr's answers to the driver's own (`Downloads.HandoffAvailability`). Each client slot gains a `category` the app sends with the grab, seeded by Detect from Prowlarr.

**Tech Stack:** Elixir/Phoenix, Req 0.7 (`form_multipart`), Ecto SQLite, Oban, ExUnit with `Req.Test` stubs. Spec: `docs/superpowers/specs/2026-10-12-download-phases-design.md` (owner decisions block). Follows `2026-10-12-download-phases.md`.

**House rules that apply:** `~/scripts/agents/agent-mix` only; test-first; placeholders in test content; no backward-compatibility paths (CLAUDE.md); Boundary declarations are the canonical dependency list.

**Named hazard (owner informed):** targets acquired before this ships carry no `download_id`; a usenet download in flight at upgrade time no longer pairs with its pursuit. The file still lands and imports through the watcher. The CHANGELOG entry says so.

**Scheduled convergence (not in this plan):** after this plan, `{:handoff, slot}` availability and `Downloads.Connectivity` both measure the app's link to a client (submit path vs poll path). Fold the hand-off integration into Connectivity in a follow-up; `docs/superpowers/specs/2026-10-12-download-phases-design.md` records it.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/media_centaur/downloads/info_hash.ex` (create) | Torrent identity from bytes or a magnet: `from_torrent/1`, `from_magnet/1`, `normalize/1` (moved out of `Acquisition.InfoHash`) |
| `lib/media_centaur/acquisition/info_hash.ex` (modify) | Keeps `from_search_result/1`, delegating; loses `resolve/2` and the fetcher |
| `lib/media_centaur/downloads/download_client.ex` (modify) | `payload` type; `add/3` callback |
| `lib/media_centaur/downloads/download_client/sabnzbd.ex` (modify) | `add/3` via `mode=addfile` |
| `lib/media_centaur/downloads/download_client/qbittorrent.ex` (modify) | `add/3` via `/api/v2/torrents/add` |
| `lib/media_centaur/downloads/client_config.ex`, `lib/media_centaur/downloads.ex` (modify) | `category` on the slot |
| `lib/media_centaur/settings/config.ex`, `lib/media_centaur/capabilities.ex` (modify) | `download_client_category`, `usenet_download_client_category` |
| `lib/media_centaur/downloads/handoff_availability.ex` (create) | Writer and probe of `{:handoff, slot}` from the driver's answers |
| `lib/media_centaur/search/prowlarr_availability.ex`, `lib/media_centaur/search/prowlarr.ex`, `lib/media_centaur/search/probe_job.ex` (modify) | Lose grab, hand-off probe, `download_client_unavailable?`; keep `list_download_clients/1` (Detect) |
| `lib/media_centaur/acquisition/release_payload.ex` (create) | Fetches a release's payload through Prowlarr's download link |
| `lib/media_centaur/acquisition/grab.ex` (create) | The one grab path |
| `lib/media_centaur/acquisition/jobs/grab_target.ex`, `lib/media_centaur/acquisition/jobs/pursue_target.ex` (modify) | Call `Grab.grab/1`; store the id |
| `priv/repo/migrations/<ts>_rename_torrent_hash_to_download_id.exs` (create) | Column rename |
| `lib/media_centaur/acquisition/target.ex`, `targets.ex`, `pursuits.ex`, `pursuits/observations.ex`, `pursuits/snapshots.ex`, `pursuits/identity.ex`, `view_models/pursuit_row.ex`, `queue_matcher.ex`, `downloads/queue_item.ex` (modify) | `download_id`; id-only pairing; `normalized_title` gone |
| `lib/media_centaur_web/live/settings_live/acquisition_section.ex`, `settings_live.ex` (modify) | Category field on both client forms; Detect seeds it |
| `lib/media_centaur_web/components/acquisition/needs_attention.ex` (modify) | Hand-off fault copy names the app, not Prowlarr |
| `test/support/download_client_stubs.ex` (modify) | `mark_torrent_ready!/0`, `mark_usenet_ready!/0` |
| `decisions/architecture/<date>-<NNN>-app-owned-grabs.md` (create) | The decision |

Branch: continue on `download-phases` after Plan 1 merges, or `git switch -c app-owned-grabs` from `main`.

---

### Task 1: `Downloads.InfoHash` — torrent identity from a payload

**Files:**
- Create: `lib/media_centaur/downloads/info_hash.ex`
- Modify: `lib/media_centaur/acquisition/info_hash.ex`
- Test: `test/media_centaur/downloads/info_hash_test.exs` (create), `test/media_centaur/acquisition/info_hash_test.exs` (modify)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Downloads.InfoHashTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Downloads.InfoHash

  @hash "0123456789abcdef0123456789abcdef01234567"

  test "from_magnet/1 reads and normalizes the btih" do
    assert InfoHash.from_magnet("magnet:?xt=urn:btih:#{String.upcase(@hash)}&dn=Sample") == @hash
    assert InfoHash.from_magnet("magnet:?dn=Sample") == nil
    assert InfoHash.from_magnet(nil) == nil
  end

  test "from_torrent/1 hashes the exact info dict span" do
    info = "d6:lengthi1e4:name6:sample12:piece lengthi1e6:pieces20:aaaaaaaaaaaaaaaaaaaae"
    torrent = "d8:announce9:udp://x/a4:info" <> info <> "e"

    expected = :sha |> :crypto.hash(info) |> Base.encode16(case: :lower)
    assert InfoHash.from_torrent(torrent) == expected
    assert InfoHash.from_torrent("not bencode") == nil
  end

  test "from_payload/1 derives the id for either torrent payload" do
    assert InfoHash.from_payload({:magnet, "magnet:?xt=urn:btih:#{@hash}"}) == @hash
    assert InfoHash.from_payload({:torrent, "junk"}) == nil
    assert InfoHash.from_payload({:nzb, "<nzb/>", "sample.nzb"}) == nil
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/info_hash_test.exs`
Expected: compile error — `MediaCentaur.Downloads.InfoHash` is undefined.

- [ ] **Step 3: Implement**

Move `from_magnet/1`, `from_torrent/1`, `normalize/1` and the private `info_span/1` family verbatim from `lib/media_centaur/acquisition/info_hash.ex` into the new module, with this moduledoc and one new function:

```elixir
defmodule MediaCentaur.Downloads.InfoHash do
  @moduledoc """
  A torrent's v1 infohash — qBittorrent's job id — from the payload the
  app hands the client: the `info` dict of `.torrent` bytes, or the
  `xt=urn:btih:` of a magnet. Always lowercase 40-char hex, or nil.

  Owned by Downloads because the qBittorrent driver answers `add/3` with
  it: the client's add call returns nothing, so the id is computed from
  the same bytes it was given. `Acquisition.InfoHash` reads the indexer's
  own fields through this module's normalization.
  """

  @doc "The job id a torrent payload carries; nil for an NZB or an unreadable torrent."
  @spec from_payload(MediaCentaur.Downloads.DownloadClient.payload()) :: String.t() | nil
  def from_payload({:torrent, bytes}), do: from_torrent(bytes)
  def from_payload({:magnet, uri}), do: from_magnet(uri)
  def from_payload({:nzb, _bytes, _name}), do: nil
  # … from_magnet/1, from_torrent/1, normalize/1, info_span/1 … moved verbatim
end
```

Rewrite `lib/media_centaur/acquisition/info_hash.ex` to:

```elixir
defmodule MediaCentaur.Acquisition.InfoHash do
  @moduledoc """
  Best-effort infohash from a search result's own fields, without network
  access: the indexer's `info_hash`, else the `magnet_url`, else a magnet
  in the `guid`. Nil for usenet and for indexers that expose none — the
  grab then learns the id from the payload (`Downloads.InfoHash.from_payload/1`).
  """

  alias MediaCentaur.Downloads.InfoHash
  alias MediaCentaur.Search.SearchResult

  @spec from_search_result(SearchResult.t()) :: String.t() | nil
  def from_search_result(%SearchResult{info_hash: info_hash, magnet_url: magnet_url, guid: guid}) do
    InfoHash.normalize(info_hash) || InfoHash.from_magnet(magnet_url) || InfoHash.from_magnet(guid)
  end
end
```

Delete `resolve/2`, `fetch/1` and the `fetcher` type. In `test/media_centaur/acquisition/info_hash_test.exs`, move the `from_magnet`/`from_torrent`/`normalize` tests to the new test file and delete the `resolve/2` tests (the grab path's tests in Task 7 cover fetching). Add `MediaCentaur.Downloads` to the `exports` of `lib/media_centaur/downloads.ex`'s `use Boundary` if `Downloads.InfoHash` is not already exported by a wildcard — read the `exports:` list and follow its pattern.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/info_hash_test.exs test/media_centaur/acquisition/info_hash_test.exs`
Expected: pass. `~/scripts/agents/agent-mix compile --warnings-as-errors` reports the two jobs still calling `InfoHash.resolve/1` — expected until Task 7.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/downloads/info_hash.ex lib/media_centaur/acquisition/info_hash.ex lib/media_centaur/downloads.ex test/media_centaur/downloads/info_hash_test.exs test/media_centaur/acquisition/info_hash_test.exs
git commit -m "refactor(downloads): InfoHash from a payload lives with the drivers"
```

---

### Task 2: `DownloadClient.add/3` on both drivers

**Files:**
- Modify: `lib/media_centaur/downloads/download_client.ex`
- Modify: `lib/media_centaur/downloads/download_client/sabnzbd.ex`
- Modify: `lib/media_centaur/downloads/download_client/qbittorrent.ex`
- Test: `test/media_centaur/downloads/download_client/sabnzbd_test.exs`, `test/media_centaur/downloads/download_client/qbittorrent_test.exs`

- [ ] **Step 1: Write the failing tests**

In `sabnzbd_test.exs`, add a describe (reuse the file's `config` setup):

```elixir
  describe "add/3" do
    test "posts the NZB as a file with the category and returns the nzo_id", %{config: config} do
      parent = self()

      Req.Test.stub(:sabnzbd, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:add, conn.method, conn.params, body})
        Req.Test.json(conn, %{"status" => true, "nzo_ids" => ["nzo_new"]})
      end)

      assert {:ok, "nzo_new"} =
               SABnzbd.add(config, {:nzb, "<nzb/>", "Sample.Show.S01E01.nzb"}, "prowlarr")

      assert_receive {:add, "POST", params, body}
      assert params["mode"] == "addfile"
      assert params["cat"] == "prowlarr"
      assert params["nzbname"] == "Sample.Show.S01E01"
      assert body =~ "<nzb/>"
      assert body =~ ~s|filename="Sample.Show.S01E01.nzb"|
    end

    test "omits the category when the slot has none", %{config: config} do
      parent = self()

      Req.Test.stub(:sabnzbd, fn conn ->
        send(parent, {:params, conn.params})
        Req.Test.json(conn, %{"status" => true, "nzo_ids" => ["nzo_new"]})
      end)

      assert {:ok, _} = SABnzbd.add(config, {:nzb, "<nzb/>", "a.nzb"}, nil)
      assert_receive {:params, params}
      refute Map.has_key?(params, "cat")
    end

    test "a refused NZB is an api_error, not an outage", %{config: config} do
      Req.Test.stub(:sabnzbd, fn conn ->
        Req.Test.json(conn, %{"status" => false, "error" => "Invalid NZB file"})
      end)

      assert {:error, {:api_error, "Invalid NZB file"}} =
               SABnzbd.add(config, {:nzb, "junk", "a.nzb"}, nil)
    end

    test "a torrent payload is refused before any request", %{config: config} do
      Req.Test.stub(:sabnzbd, fn _conn -> flunk("no request for a wrong-protocol payload") end)
      assert {:error, :unsupported_payload} = SABnzbd.add(config, {:magnet, "magnet:?x"}, nil)
    end
  end
```

In `qbittorrent_test.exs`, add (reuse its `config`):

```elixir
  describe "add/3" do
    @hash "0123456789abcdef0123456789abcdef01234567"

    test "adds a magnet by url with the category and answers with its infohash", %{config: config} do
      parent = self()

      Req.Test.stub(:qbittorrent, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(parent, {:add, conn.request_path, body})
        Plug.Conn.send_resp(conn, 200, "Ok.")
      end)

      magnet = "magnet:?xt=urn:btih:#{@hash}&dn=Sample"
      assert {:ok, @hash} = QBittorrent.add(config, {:magnet, magnet}, "prowlarr")

      assert_receive {:add, "/api/v2/torrents/add", body}
      assert body =~ "category=prowlarr"
      assert body =~ URI.encode_www_form(magnet)
    end

    test "adds torrent bytes as a file and hashes them", %{config: config} do
      info = "d6:lengthi1e4:name6:sample12:piece lengthi1e6:pieces20:aaaaaaaaaaaaaaaaaaaae"
      torrent = "d4:info" <> info <> "e"
      expected = :sha |> :crypto.hash(info) |> Base.encode16(case: :lower)

      Req.Test.stub(:qbittorrent, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ ~s|name="torrents"|
        Plug.Conn.send_resp(conn, 200, "Ok.")
      end)

      assert {:ok, ^expected} = QBittorrent.add(config, {:torrent, torrent}, nil)
    end

    test "qBittorrent's \"Fails.\" is a refusal", %{config: config} do
      Req.Test.stub(:qbittorrent, fn conn -> Plug.Conn.send_resp(conn, 200, "Fails.") end)

      assert {:error, {:rejected, "Fails."}} =
               QBittorrent.add(config, {:magnet, "magnet:?xt=urn:btih:#{@hash}"}, nil)
    end

    test "an NZB payload is refused before any request", %{config: config} do
      Req.Test.stub(:qbittorrent, fn _conn -> flunk("no request") end)
      assert {:error, :unsupported_payload} = QBittorrent.add(config, {:nzb, "x", "a.nzb"}, nil)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/download_client/`
Expected: `add/3` undefined on both drivers.

- [ ] **Step 3: Implement the behaviour**

In `download_client.ex`, after `@type driver_state`:

```elixir
  @typedoc """
  What the app hands a client: an NZB's bytes with the filename the
  client names the job after, a `.torrent`'s bytes, or a magnet URI.
  Fetched by `Acquisition.ReleasePayload`; each driver accepts its
  protocol's shapes and refuses the other with `:unsupported_payload`.
  """
  @type payload :: {:nzb, binary(), String.t()} | {:torrent, binary()} | {:magnet, String.t()}

  @doc """
  Submits a release and answers with the client's id for the job —
  SABnzbd's `nzo_id`, qBittorrent's infohash. `category` is the slot's
  configured category or nil. A refusal of the release itself
  (`{:api_error, _}`, `{:rejected, _}`, 4xx) is distinct from the
  client being unreachable (transport error, `:auth_failed`, 5xx):
  `Acquisition.Grab.outage?/1` tells them apart.
  """
  @callback add(ClientConfig.t(), payload(), category :: String.t() | nil) ::
              {:ok, id :: String.t()} | {:error, term()}
```

- [ ] **Step 4: Implement SABnzbd**

Add to the moduledoc's table: `| Add | POST mode=addfile (multipart name=<nzb>, nzbname, cat) |`. Add:

```elixir
  @impl true
  def add(%ClientConfig{} = config, {:nzb, bytes, filename}, category) do
    params =
      [mode: "addfile", nzbname: Path.rootname(filename)]
      |> then(fn params -> if category, do: Keyword.put(params, :cat, category), else: params end)

    case post_api(config, params, form_multipart: [name: {bytes, filename: filename}]) do
      {:ok, %{"nzo_ids" => [id | _]}} -> {:ok, id}
      {:ok, body} -> {:error, {:api_error, "no nzo_id in #{inspect(body)}"}}
      {:error, reason} -> {:error, reason}
    end
  end

  def add(%ClientConfig{}, _payload, _category), do: {:error, :unsupported_payload}
```

Refactor `get_api/2` so the request shape is shared: extract the client construction and the response classification into `api_request/3`:

```elixir
  defp get_api(config, params), do: api_request(config, params, [])
  defp post_api(config, params, opts), do: api_request(config, params, [{:method, :post} | opts])

  defp api_request(%ClientConfig{} = config, params, opts) do
    client =
      MediaCentaur.HttpClient.new(__MODULE__, upstream: :sabnzbd, base_url: config.url, retry: false)

    api_key = MediaCentaur.Secret.expose(config.api_key) || ""
    params = Keyword.merge([output: "json", apikey: api_key], params)
    {method, opts} = Keyword.pop(opts, :method, :get)

    case Req.request(client, [method: method, url: "/api", params: params] ++ opts) do
      # … the existing three branches of get_api/2, unchanged …
    end
  end
```

- [ ] **Step 5: Implement qBittorrent**

Add to the endpoint table: `| Add | POST /api/v2/torrents/add |`. Add:

```elixir
  @impl true
  def add(%ClientConfig{} = config, {:magnet, uri} = payload, category) do
    submit(config, payload, form: [urls: uri] ++ category_form(category))
  end

  def add(%ClientConfig{} = config, {:torrent, bytes} = payload, category) do
    submit(config, payload,
      form_multipart: [torrents: {bytes, filename: "release.torrent"}] ++ category_form(category)
    )
  end

  def add(%ClientConfig{}, _payload, _category), do: {:error, :unsupported_payload}

  defp category_form(nil), do: []
  defp category_form(category), do: [category: category]

  # qBittorrent answers 200 "Ok." or 200 "Fails." — the body is the verdict.
  # The add call returns no id, so the infohash comes from the payload.
  defp submit(config, payload, req_opts) do
    case InfoHash.from_payload(payload) do
      nil ->
        {:error, :unreadable_payload}

      hash ->
        attempt(config, fn c ->
          case Req.post(c, [url: "/api/v2/torrents/add"] ++ req_opts) do
            {:ok, %{status: 200, body: "Ok." <> _}} -> {:ok, hash}
            {:ok, %{status: 200, body: body}} -> {:error, {:rejected, body}}
            {:ok, %{status: 403, body: body}} -> {:error, {:http_error, 403, body}}
            {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
            {:error, reason} -> {:error, reason}
          end
        end)
    end
  end
```

with `alias MediaCentaur.Downloads.InfoHash`.

- [ ] **Step 6: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/download_client/`
Expected: pass. If `Req.Test` does not surface multipart bodies as a string containing `filename=`, read the body with `Plug.Conn.read_body/1` as the tests do — `Req.Test` delivers the raw request body.

- [ ] **Step 7: Commit**

```bash
git add lib/media_centaur/downloads/download_client.ex lib/media_centaur/downloads/download_client/sabnzbd.ex lib/media_centaur/downloads/download_client/qbittorrent.ex test/media_centaur/downloads/download_client/
git commit -m "feat(downloads): DownloadClient.add/3 — the app submits releases to the client"
```

---

### Task 3: Category on each client slot

**Files:**
- Modify: `lib/media_centaur/settings/config.ex` (`@runtime_settable_keys`, defaults)
- Modify: `lib/media_centaur/capabilities.ex` (`@integration_fields`)
- Modify: `lib/media_centaur/downloads/client_config.ex`, `lib/media_centaur/downloads.ex`
- Test: `test/media_centaur/downloads_test.exs` (or wherever `configured_clients/0` is tested — `grep -rl configured_clients test`)

- [ ] **Step 1: Write the failing test**

In the test file that covers `configured_clients/0`, add:

```elixir
  test "each slot carries its category, defaulting to prowlarr" do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.merge(config, %{
        download_client_type: "qbittorrent",
        download_client_url: "http://qbit.test",
        download_client_category: "movies",
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://sab.test"
      })
    )

    on_exit(fn -> :persistent_term.put({MediaCentaur.Settings.Config, :config}, config) end)

    assert [%{protocol: :torrent, category: "movies"}, %{protocol: :usenet, category: "prowlarr"}] =
             MediaCentaur.Downloads.configured_clients()
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: `category` is not a key of `ClientConfig`.

- [ ] **Step 3: Implement**

`config.ex`: add `:download_client_category` after `:download_client_password` and `:usenet_download_client_category` after `:usenet_download_client_api_key` in `@runtime_settable_keys`; in the defaults map add `download_client_category: "prowlarr"` and `usenet_download_client_category: "prowlarr"` beside their siblings, with a comment:

```elixir
      # The category the app files a grab under at the client; the client's
      # completed folder follows it, so it must land inside a watched media
      # directory. "prowlarr" is what a prowlarr-stack install's clients use.
```

`capabilities.ex` `@integration_fields`: add `download_client_category: :clearable` and `usenet_download_client_category: :clearable`.

`client_config.ex`: add `:category` to the struct and `category: String.t() | nil` to the type, with the comment "The category grabs are filed under at this client (`DownloadClient.add/3`)". `downloads.ex`: `category: Config.get(:download_client_category)` in `torrent_slot/0`, `category: Config.get(:usenet_download_client_category)` in `usenet_slot/0`.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads_test.exs test/media_centaur/capabilities_test.exs`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/settings/config.ex lib/media_centaur/capabilities.ex lib/media_centaur/downloads/client_config.ex lib/media_centaur/downloads.ex test/
git commit -m "feat(downloads): a category per client slot"
```

---

### Task 4: Settings — the Category field and Detect seeds it

**Files:**
- Modify: `lib/media_centaur/search/prowlarr.ex:372-389` (`parse_download_client/1`)
- Modify: `lib/media_centaur_web/live/settings_live.ex:1735-1760` (detected maps)
- Modify: `lib/media_centaur_web/live/settings_live/acquisition_section.ex` (both client forms)
- Test: `test/media_centaur/search/prowlarr_test.exs` (the `list_download_clients` test), `test/media_centaur_web/live/settings_live_test.exs` (the acquisition form tests — `grep -n usenet_download_client_url test/media_centaur_web/live/settings_live*`)

- [ ] **Step 1: Write the failing tests**

In the Prowlarr test that stubs `/api/v1/downloadclient`, add `%{"name" => "category", "value" => "prowlarr"}` to the fixture's fields and assert `category: "prowlarr"` on the parsed map.

In the Settings test that saves the usenet form, post `"usenet_download_client_category" => "tv"` along with the URL and assert `MediaCentaur.Settings.Config.get(:usenet_download_client_category) == "tv"`. Add the mirror for the torrent form. Add a render assertion that the open usenet form contains `name="usenet_download_client_category"`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: the parsed map lacks `category`; the form has no such field.

- [ ] **Step 3: Implement**

`prowlarr.ex` `parse_download_client/1`: add `category: blank_to_nil(fields["category"]),` and mention it in the `@doc`.

`settings_live.ex` detected maps: `%{type: client.type, url: client.url, username: client.username, category: client.category}` and `%{type: client.type, url: client.url, category: client.category}`.

`acquisition_section.ex`: in the torrent form, after the Password field:

```heex
              <.settings_field
                label="Category"
                description="The client files the download under it, and its completed folder follows. Keep it inside a watched media directory."
                layout={:stacked}
              >
                <.settings_input
                  name="download_client_category"
                  value={
                    @rows.download_client.prefill[:category] ||
                      @config[:download_client_category]
                  }
                  placeholder="prowlarr"
                  mono
                />
              </.settings_field>
```

and in the usenet form, after the API key field, the same with `usenet_download_client_category` and `@rows.usenet_download_client`. Check `load_config/0` in `settings_live.ex` exposes the two new keys in `@config` (it builds the map from `Config.get` per key — add both).

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/search/prowlarr_test.exs test/media_centaur_web/live/settings_live_test.exs`
Expected: pass. The connection row stories (`storybook/settings/*`) do not render this form, so no story change.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/search/prowlarr.ex lib/media_centaur_web/live/settings_live.ex lib/media_centaur_web/live/settings_live/acquisition_section.ex test/
git commit -m "feat(settings): category on each download client, seeded by Detect from Prowlarr"
```

---

### Task 5: `Downloads.HandoffAvailability` — the driver answers for the hand-off

**Files:**
- Create: `lib/media_centaur/downloads/handoff_availability.ex`
- Modify: `lib/media_centaur/integration_availability.ex:85-95` (`available?/1` doc and gate)
- Modify: `lib/media_centaur/search/prowlarr_availability.ex` (remove `observe_grab/2`, `probe_handoff/1`, `fold_slot/3`, `report_handoff/2`; `enqueue_probe/1` becomes `:prowlarr`-only)
- Modify: `lib/media_centaur/search/probe_job.ex:61-75` (the `"handoff"` branch)
- Modify: `lib/media_centaur/search/prowlarr.ex` (remove `grab/2`, `grab_outage?/1`, `download_client_unavailable?/1`, `test_download_clients/1`)
- Modify: `lib/media_centaur/downloads.ex` (`use Boundary` deps gains `MediaCentaur.IntegrationAvailability`; exports `HandoffAvailability`)
- Test: `test/media_centaur/downloads/handoff_availability_test.exs` (create); `test/media_centaur/search/prowlarr_availability_test.exs`, `test/media_centaur/search/probe_job_test.exs` (the hand-off cases move)

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Downloads.HandoffAvailabilityTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Downloads.HandoffAvailability
  alias MediaCentaur.DownloadClientStubs
  alias MediaCentaur.IntegrationAvailability

  setup do
    DownloadClientStubs.setup_sabnzbd_client()
    DownloadClientStubs.mark_usenet_ready!()
    :ok
  end

  describe "observe/2" do
    test "a successful add is the slot up" do
      HandoffAvailability.observe(:usenet, {:error, %Req.TransportError{reason: :econnrefused}})
      refute IntegrationAvailability.up?({:handoff, :usenet})

      HandoffAvailability.observe(:usenet, {:ok, "nzo"})
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end

    test "an unreachable or rejecting client is down; a refused release is not" do
      assert {:changed, {:down, _since, :client_unavailable}} =
               HandoffAvailability.observe(:usenet, {:error, :auth_failed})

      HandoffAvailability.observe(:usenet, {:ok, "nzo"})

      assert :unchanged = HandoffAvailability.observe(:usenet, {:error, {:api_error, "Invalid NZB"}})
      assert IntegrationAvailability.up?({:handoff, :usenet})

      assert :unchanged = HandoffAvailability.observe(:torrent, {:error, {:rejected, "Fails."}})
    end
  end

  describe "probe/0" do
    test "tests each configured slot's client and folds the answer" do
      Req.Test.stub(:sabnzbd, fn conn -> Plug.Conn.send_resp(conn, 500, "down") end)
      HandoffAvailability.observe(:usenet, {:error, :auth_failed})

      assert :ok = HandoffAvailability.probe()
      refute IntegrationAvailability.up?({:handoff, :usenet})

      Req.Test.stub(:sabnzbd, fn conn -> Req.Test.json(conn, %{"queue" => %{"slots" => []}}) end)
      assert :ok = HandoffAvailability.probe()
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end

    test "a slot with no configured client is reported up — there is no link to break" do
      assert :ok = HandoffAvailability.probe()
      assert IntegrationAvailability.up?({:handoff, :torrent})
    end
  end
end
```

Add to `test/support/download_client_stubs.ex`:

```elixir
  @doc "Records a passing connection test for the usenet slot so `Capabilities.client_ready?(:usenet)` is true."
  def mark_usenet_ready! do
    %{status: :ok} = MediaCentaur.Capabilities.save_test_result(:usenet_download_client, :ok)
    true = MediaCentaur.Capabilities.client_ready?(:usenet)
    :ok
  end

  @doc "The torrent-slot mirror of `mark_usenet_ready!/0`."
  def mark_torrent_ready! do
    %{status: :ok} = MediaCentaur.Capabilities.save_test_result(:download_client, :ok)
    true = MediaCentaur.Capabilities.client_ready?(:torrent)
    :ok
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/handoff_availability_test.exs`
Expected: `HandoffAvailability` undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Downloads.HandoffAvailability do
  @moduledoc """
  The one writer of `{:handoff, slot}` availability
  (`MediaCentaur.IntegrationAvailability`): whether the app can hand a
  release to the slot's download client.

  `Acquisition.Grab` calls `observe/2` with the driver's `add/3` answer.
  A transport error, a rejected credential or a 5xx says the client is
  unavailable; a refusal of the release itself (`{:api_error, _}`,
  `{:rejected, _}`, a 4xx) says nothing about the link and moves
  nothing. On a transition to down the writer enqueues
  `MediaCentaur.Search.ProbeJob` for `"handoff"`, whose `probe/0` runs
  each configured driver's `test_connection/1` until the slot answers.

  A slot with no configured client is reported up: there is no link to
  break, and a grab of that protocol fails on `Dispatcher.driver_for/1`
  with its own reason.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.ProbeJob

  @type verdict :: :unchanged | {:changed, IntegrationAvailability.Status.state()}

  @doc "Folds a driver's `add/3` outcome into the slot's hand-off availability."
  @spec observe(:torrent | :usenet, {:ok, term()} | {:error, term()}) :: verdict()
  def observe(slot, {:ok, _id}), do: report(slot, :up)

  def observe(slot, {:error, reason}) do
    if unavailable?(reason), do: report(slot, {:down, :client_unavailable}), else: :unchanged
  end

  @doc "Tests every configured slot's client from here and folds the answers."
  @spec probe() :: :ok
  def probe do
    for slot <- IntegrationAvailability.handoff_slots() do
      case Dispatcher.driver_for(slot) do
        {:ok, {config, driver}} ->
          case driver.test_connection(config) do
            :ok -> report(slot, :up)
            {:error, _reason} -> report(slot, {:down, :client_unavailable})
          end

        {:error, _not_configured} ->
          report(slot, :up)
      end
    end

    :ok
  end

  defp unavailable?(%Req.TransportError{}), do: true
  defp unavailable?(:auth_failed), do: true
  defp unavailable?({:http_error, status, _body}) when status >= 500, do: true
  defp unavailable?({:http_error, status}) when status >= 500, do: true
  defp unavailable?(_release_refused), do: false

  defp report(slot, observation) do
    case IntegrationAvailability.report({:handoff, slot}, observation) do
      {:changed, {:down, _since, _reason}} = changed ->
        enqueue_probe()
        changed

      other ->
        other
    end
  end

  defp enqueue_probe do
    if Capabilities.download_client_ready?() do
      job = ProbeJob.new(%{integration: "handoff"}, schedule_in: ProbeJob.cadence_seconds())

      case Oban.insert(job) do
        {:ok, _job} -> :ok
        {:error, reason} -> Log.warning(:acquisition, "hand-off probe not enqueued — #{inspect(reason)}", mc_incident: :skip)
      end
    end

    :ok
  end
end
```

Check the Boundary graph: `Downloads` now depends on `IntegrationAvailability` and `Search` (for `ProbeJob`). If `Search` already depends on `Downloads` that is a cycle — then move the enqueue into `ProbeJob`'s own context by having `IntegrationAvailability.report/3` callers enqueue through a tiny `MediaCentaur.Search.ProbeJob.enqueue_handoff/0` called from `Acquisition.Grab` instead (Acquisition already depends on both). Decide by running `~/scripts/agents/agent-mix compile` after adding the deps; the Boundary compiler names the cycle.

`integration_availability.ex`: `available?({:handoff, slot})` becomes `Capabilities.client_ready?(slot) and up?(integration)`; rewrite the paragraph above it: "A hand-off needs the slot's own client configured and tested: the hand-off is the app's link to that client."

`probe_job.ex` `"handoff"` branch: replace `ProwlarrAvailability.probe_handoff()` with `HandoffAvailability.probe()`; the moduledoc line about `downloadclient/testall` becomes "each driver's `test_connection/1` for `\"handoff\"`".

`prowlarr_availability.ex`: delete `observe_grab/2`, `probe_handoff/1`, `fold_slot/3`, `report_handoff/2`; `enqueue_probe/1` keeps only the `"prowlarr"` case; rewrite the moduledoc's first paragraph and drop the hand-off probe paragraph. `prowlarr.ex`: delete `grab/2`, `grab_outage?/1`, `download_client_unavailable?/1`, `test_download_clients/1` and the `| Grab |` table row; keep `list_download_clients/1`.

Move the hand-off tests out of `prowlarr_availability_test.exs` and `probe_job_test.exs` (delete the ones that stub `downloadclient/testall`; the probe job test for `"handoff"` now stubs `:sabnzbd`/`:qbittorrent` and asserts the slot flips).

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/downloads/handoff_availability_test.exs test/media_centaur/search/ test/media_centaur/integration_availability_test.exs`
Expected: pass. Compile still warns about `Prowlarr.grab/1` callers until Task 7.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/downloads/handoff_availability.ex lib/media_centaur/downloads.ex lib/media_centaur/integration_availability.ex lib/media_centaur/search/ test/
git commit -m "refactor(availability): the hand-off is the app's link to the client; the driver answers for it"
```

---

### Task 6: `Acquisition.ReleasePayload` — fetch the release through Prowlarr

**Files:**
- Create: `lib/media_centaur/acquisition/release_payload.ex`
- Test: `test/media_centaur/acquisition/release_payload_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Acquisition.ReleasePayloadTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.ReleasePayload
  alias MediaCentaur.ProwlarrStubs
  alias MediaCentaur.Search.SearchResult

  setup do
    ProwlarrStubs.mark_ready!()
    :ok
  end

  defp result(overrides) do
    struct!(
      %SearchResult{
        title: "Sample.Show.S01E01.1080p.WEB-DL",
        guid: "g1",
        indexer_id: 1,
        protocol: :usenet,
        download_url: "http://prowlarr.test/1/download?apikey=k&link=abc"
      },
      overrides
    )
  end

  test "a usenet release is its NZB bytes, named after the release" do
    Req.Test.stub(:prowlarr, fn conn ->
      assert conn.request_path == "/1/download"
      conn |> Plug.Conn.put_resp_content_type("application/x-nzb") |> Plug.Conn.send_resp(200, "<nzb/>")
    end)

    assert {:ok, {:nzb, "<nzb/>", "Sample.Show.S01E01.1080p.WEB-DL.nzb"}} =
             ReleasePayload.fetch(result(%{}))
  end

  test "a torrent release with a magnet needs no request" do
    Req.Test.stub(:prowlarr, fn _conn -> flunk("no request for a magnet") end)
    magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"

    assert {:ok, {:magnet, ^magnet}} = ReleasePayload.fetch(result(%{protocol: :torrent, magnet_url: magnet}))
  end

  test "a torrent release follows a magnet redirect or takes the .torrent body" do
    magnet = "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567"

    Req.Test.stub(:prowlarr, fn conn ->
      conn |> Plug.Conn.put_resp_header("location", magnet) |> Plug.Conn.send_resp(302, "")
    end)

    assert {:ok, {:magnet, ^magnet}} = ReleasePayload.fetch(result(%{protocol: :torrent}))

    Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 200, "d4:infod0ee") end)
    assert {:ok, {:torrent, "d4:infod0ee"}} = ReleasePayload.fetch(result(%{protocol: :torrent}))
  end

  test "a release Prowlarr cannot serve is refused; an unreachable Prowlarr is an outage" do
    Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 404, "gone") end)
    assert {:error, {:fetch, {:http_error, 404, _}}} = ReleasePayload.fetch(result(%{}))

    Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, {:fetch, %Req.TransportError{}}} = ReleasePayload.fetch(result(%{}))
  end

  test "a release without a download link cannot be fetched" do
    assert {:error, :no_download_url} = ReleasePayload.fetch(result(%{download_url: nil}))
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Expected: `ReleasePayload` undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule MediaCentaur.Acquisition.ReleasePayload do
  @moduledoc """
  Fetches what the app hands the download client for a release
  (`DownloadClient.payload/0`), through Prowlarr's `download_url` — the
  proxy link Prowlarr serves for every indexer, so the request lands on
  the Prowlarr host whichever indexer served the release.

  A usenet link serves the NZB; the payload names the job after the
  release title so the client's name and the target's `release_title`
  agree. A torrent link either redirects to a magnet or serves the
  `.torrent` body; a result that already carries a magnet needs no
  request.

  Fetch outcomes fold into `:prowlarr` availability
  (`ProwlarrAvailability.observe_request/1`): an unreachable Prowlarr is
  an outage for every grab, a 4xx is this release's problem.
  """

  alias MediaCentaur.Downloads.DownloadClient
  alias MediaCentaur.Search.ProwlarrAvailability
  alias MediaCentaur.Search.SearchResult

  @spec fetch(SearchResult.t()) :: {:ok, DownloadClient.payload()} | {:error, term()}
  def fetch(%SearchResult{protocol: :torrent, magnet_url: "magnet:" <> _ = magnet}), do: {:ok, {:magnet, magnet}}
  def fetch(%SearchResult{download_url: nil}), do: {:error, :no_download_url}

  def fetch(%SearchResult{download_url: url} = result) when is_binary(url) do
    case request(url) do
      {:ok, %{status: status} = resp} when status in 300..399 ->
        case Req.Response.get_header(resp, "location") do
          ["magnet:" <> _ = magnet | _] when result.protocol == :torrent -> {:ok, {:magnet, magnet}}
          _ -> {:error, {:fetch, {:redirect, status}}}
        end

      {:ok, %{status: 200, body: body}} when is_binary(body) and result.protocol == :usenet ->
        {:ok, {:nzb, body, "#{result.title}.nzb"}}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, {:torrent, body}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:fetch, {:http_error, status, body}}}

      {:error, reason} ->
        {:error, {:fetch, reason}}
    end
  end

  defp request(url) do
    client =
      MediaCentaur.HttpClient.new(__MODULE__,
        upstream: :prowlarr,
        redirect: false,
        decode_body: false,
        receive_timeout: 15_000
      )

    outcome = Req.get(client, url: url)
    ProwlarrAvailability.observe_request(availability_view(outcome))
    outcome
  end

  defp availability_view({:ok, %{status: status, body: body}}) when status >= 400, do: {:error, {:http_error, status, body}}
  defp availability_view({:ok, _resp}), do: :ok
  defp availability_view({:error, reason}), do: {:error, reason}
end
```

(`Acquisition` already depends on `Search` and `HttpClient`; confirm `MediaCentaur.HttpClient` is in `Acquisition`'s `use Boundary` deps — `InfoHash` used it, so it is.)

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/release_payload_test.exs`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add lib/media_centaur/acquisition/release_payload.ex test/media_centaur/acquisition/release_payload_test.exs
git commit -m "feat(acquisition): ReleasePayload — the release's bytes through Prowlarr's download link"
```

---

### Task 7: `Acquisition.Grab` and the two jobs

**Files:**
- Create: `lib/media_centaur/acquisition/grab.ex`
- Modify: `lib/media_centaur/acquisition/jobs/grab_target.ex:59-100`
- Modify: `lib/media_centaur/acquisition/jobs/pursue_target.ex:405-470`
- Modify: `lib/media_centaur/acquisition/target.ex:296-326` (`acquire_changeset/5` takes the id)
- Test: `test/media_centaur/acquisition/grab_test.exs` (create), `test/media_centaur/acquisition/jobs/grab_target_test.exs`, `test/media_centaur/acquisition/jobs/pursue_target_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.Acquisition.GrabTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Grab
  alias MediaCentaur.{DownloadClientStubs, ProwlarrStubs}
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.Search.SearchResult

  setup do
    ProwlarrStubs.mark_ready!()
    DownloadClientStubs.setup_sabnzbd_client()
    DownloadClientStubs.mark_usenet_ready!()
    Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 200, "<nzb/>") end)
    :ok
  end

  defp usenet_release do
    %SearchResult{
      title: "Sample.Show.S01E01.1080p.WEB-DL",
      guid: "g1",
      indexer_id: 1,
      protocol: :usenet,
      download_url: "http://prowlarr.test/1/download?apikey=k&link=abc"
    }
  end

  test "fetches the payload, hands it to the slot's client with its category, returns the job id" do
    parent = self()

    Req.Test.stub(:sabnzbd, fn conn ->
      send(parent, {:sab, conn.params})
      Req.Test.json(conn, %{"status" => true, "nzo_ids" => ["nzo_1"]})
    end)

    assert {:ok, "nzo_1"} = Grab.grab(usenet_release())
    assert_receive {:sab, %{"mode" => "addfile", "cat" => "prowlarr"}}
    assert IntegrationAvailability.up?({:handoff, :usenet})
  end

  test "an unreachable client is an outage and marks the hand-off down" do
    Req.Test.stub(:sabnzbd, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, reason} = Grab.grab(usenet_release())
    assert Grab.outage?(reason)
    refute IntegrationAvailability.up?({:handoff, :usenet})
  end

  test "a refused release is not an outage" do
    Req.Test.stub(:sabnzbd, fn conn -> Req.Test.json(conn, %{"status" => false, "error" => "Invalid NZB file"}) end)

    assert {:error, {:api_error, "Invalid NZB file"}} = Grab.grab(usenet_release())
    refute Grab.outage?({:api_error, "Invalid NZB file"})
  end

  test "an unreachable Prowlarr is an outage; a release it cannot serve is not" do
    Req.Test.stub(:prowlarr, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
    assert {:error, {:fetch, _} = reason} = Grab.grab(usenet_release())
    assert Grab.outage?(reason)

    Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
    assert {:error, {:fetch, _} = reason} = Grab.grab(usenet_release())
    refute Grab.outage?(reason)
  end

  test "no client for the protocol is not an outage" do
    assert {:error, :not_configured} = Grab.grab(%{usenet_release() | protocol: :torrent})
    refute Grab.outage?(:not_configured)
  end
end
```

In `grab_target_test.exs`: add `DownloadClientStubs.setup_sabnzbd_client()` and `DownloadClientStubs.mark_usenet_ready!()` to `setup`; give `chosen_release/0` a `download_url: "http://prowlarr.test/1/download?apikey=k&link=abc"`; rewrite `grab_reply/1` as:

```elixir
  # Prowlarr serves the NZB; SABnzbd answers the add with `reply`.
  defp grab_reply(reply) do
    Req.Test.stub(:prowlarr, fn conn -> Plug.Conn.send_resp(conn, 200, "<nzb/>") end)
    Req.Test.stub(:sabnzbd, reply)
  end
```

and update each test's reply: accepted → `&Req.Test.json(&1, %{"status" => true, "nzo_ids" => ["nzo_1"]})` and assert `Repo.reload!(target).download_id == "nzo_1"`; refused → `&Req.Test.json(&1, %{"status" => false, "error" => "Invalid NZB file"})`; "Prowlarr down" stays (no request to Prowlarr); client-unavailable → `&Req.Test.transport_error(&1, :econnrefused)`. Do the same in `pursue_target_test.exs` for its grab cases (grep `api/v1/search` there).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/grab_test.exs`
Expected: `Grab` undefined.

- [ ] **Step 3: Implement `Grab`**

```elixir
defmodule MediaCentaur.Acquisition.Grab do
  @moduledoc """
  The one grab path: the app hands a chosen release to the download
  client itself and learns the client's job id on the spot.

  Prowlarr is search only. Its grab endpoint handed the release to
  *Prowlarr's* client and told the app nothing about the job, so a
  usenet pursuit paired by title until the client renamed the job — and
  a job still fetching its NZB, named after the URL, never paired at
  all. Now `ReleasePayload.fetch/1` pulls the release through Prowlarr's
  download link, the protocol slot's driver adds it
  (`DownloadClient.add/3`) under the slot's category, and the id comes
  back: SABnzbd's `nzo_id`, qBittorrent's infohash.

  The driver's answer folds into `{:handoff, protocol}` availability
  (`Downloads.HandoffAvailability.observe/2`); the fetch folds into
  `:prowlarr`. `outage?/1` is what the jobs ask to choose between
  holding the target for the probe cadence and charging an attempt.
  """

  alias MediaCentaur.Downloads.DownloadClient.Dispatcher
  alias MediaCentaur.Downloads.HandoffAvailability
  alias MediaCentaur.Acquisition.ReleasePayload
  alias MediaCentaur.Search.SearchResult

  @spec grab(SearchResult.t()) :: {:ok, String.t()} | {:error, term()}
  def grab(%SearchResult{protocol: protocol} = result) when protocol in [:torrent, :usenet] do
    with {:ok, {config, driver}} <- Dispatcher.driver_for(protocol),
         {:ok, payload} <- ReleasePayload.fetch(result) do
      outcome = driver.add(config, payload, config.category)
      HandoffAvailability.observe(protocol, outcome)
      outcome
    end
  end

  def grab(%SearchResult{}), do: {:error, :unknown_protocol}

  @doc """
  Whether a grab error is about the infrastructure — Prowlarr or the
  client unreachable, a rejected credential, a 5xx — rather than about
  the release. The jobs hold on an outage and charge an attempt for a
  refusal, so a release the client keeps refusing is paced by the
  attempt ladder instead of retried at the probe cadence.
  """
  @spec outage?(term()) :: boolean()
  def outage?({:fetch, reason}), do: outage?(reason)
  def outage?(%Req.TransportError{}), do: true
  def outage?(:auth_failed), do: true
  def outage?({:http_error, status, _body}) when status >= 500, do: true
  def outage?({:http_error, status}) when status >= 500, do: true
  def outage?(_release_refused), do: false
end
```

- [ ] **Step 4: Wire the jobs and the changeset**

`target.ex`: `acquire_changeset(target, quality, release_title, prowlarr_guid, download_id)` — same body, the last argument is required (no default), `maybe_put_hash/2` becomes `put_change(changeset, :download_id, id)` with no nil clause (the grab always has an id). Rewrite its `@doc`: "`download_id` is the client's job id from the grab (`Acquisition.Grab.grab/1`) — the exact key the pursuit pairs with its live job by." (The column rename itself is Task 8; name the field `download_id` here and run the two tasks' tests together.)

`grab_target.ex`:

```elixir
  defp grab(target, release) do
    cond do
      not Capabilities.prowlarr_ready?() -> {:snooze, @unconfigured_snooze_seconds}
      not Capabilities.client_ready?(release.protocol) -> {:snooze, @unconfigured_snooze_seconds}
      not IntegrationAvailability.up?(:prowlarr) -> {:snooze, ProbeJob.cadence_seconds()}
      handoff_down?(release) -> hold(target)
      true -> hand_off(target, release)
    end
  end

  defp hand_off(target, release) do
    case Grab.grab(release) do
      {:ok, download_id} -> land(target, release, download_id)
      {:error, reason} -> if Grab.outage?(reason), do: hold(target), else: refuse(target, reason)
    end
  end

  defp land(target, release, download_id) do
    quality = Quality.label(release.quality)

    {:ok, acquired} =
      target
      |> Target.acquire_changeset(quality, release.title, release.guid, download_id)
      |> Repo.update()
    # … unchanged from here …
```

`Capabilities.client_ready?/1` takes `:torrent | :usenet`; guard `release.protocol` with the `@handoff_slots` check already in the file (a nil protocol snoozes as unconfigured). Replace `alias MediaCentaur.Search.Prowlarr` with `alias MediaCentaur.Acquisition.Grab`; drop `InfoHash`.

`pursue_target.ex` `grab_found/5`: `case Grab.grab(result) do {:ok, download_id} -> … Target.acquire_changeset(target, quality_label, result.title, result.guid, download_id) …; {:error, reason} -> … if Grab.outage?(reason) …`. Update the comment "Prowlarr has just pushed the release" to "The client has just been handed the release". Add the `client_ready?` gate beside the `prowlarr_ready?` one in its `perform/1` preamble (grep `prowlarr_ready?` in the file). Drop the `Prowlarr` and `InfoHash` aliases if unused.

`grab_target.ex` moduledoc line 25 and `target.ex` lines 14, 19, 52, `target_status.ex` lines 39, 57, 97, `stage.ex` line 27, `acquisition.ex` line 123: replace "Prowlarr accepted" with "the download client accepted".

- [ ] **Step 5: Run the tests**

Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/grab_test.exs test/media_centaur/acquisition/jobs/`
Expected: pass once Task 8's rename is in (run Tasks 7 and 8 back to back; commit after both are green).

---

### Task 8: `torrent_hash` becomes `download_id`; pairing by id only

**Files:**
- Create: `priv/repo/migrations/20261013120000_rename_torrent_hash_to_download_id.exs`
- Modify: `lib/media_centaur/acquisition/target.ex`, `targets.ex:270-335`, `pursuits.ex:673-734,804`, `pursuits/observations.ex:70-95`, `pursuits/snapshots.ex:81`, `pursuits/identity.ex`, `view_models/pursuit_row.ex:33-74`, `queue_matcher.ex`, `downloads/queue_item.ex` (`normalized_title`)
- Modify: `test/support/factory.ex:1399` and every test listed by `grep -rl "torrent_hash\|normalized_title\|find_contained\|containment" test`

- [ ] **Step 1: Write the failing tests**

In `test/media_centaur/acquisition/queue_matcher_test.exs`:
- rename every `torrent_hash:` to `download_id:`;
- delete the describe blocks for title/containment pairing;
- add:

```elixir
    test "pairs by id only — a same-titled stranger is not the download" do
      row = row(%{download_id: nil, release_title: "Sample.Movie.2010.1080p.WEB-DL"})
      stranger = item("hash-stranger", "Sample.Movie.2010.1080p.WEB-DL", %{})

      assert {[%{download: nil}], [^stranger]} = QueueMatcher.match([row], [stranger])
    end
```

(`row/1` and `item/3` are the file's own builders.) In `test/media_centaur/acquisition/target_test.exs` assert `acquire_changeset/5` writes `download_id`. In `observations_test.exs` and `snapshots_test.exs` rename the field.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: unknown field `download_id`.

- [ ] **Step 3: Implement**

Migration:

```elixir
defmodule MediaCentaur.Repo.Migrations.RenameTorrentHashToDownloadId do
  use Ecto.Migration

  # The column has held SABnzbd nzo_ids beside qBittorrent infohashes since
  # usenet grabs were observed; it is the client's job id, so it is named
  # for what it is. No data moves.
  def change do
    rename table(:acquisition_targets), :torrent_hash, to: :download_id
  end
end
```

`target.ex`: `field :download_id, :string` with the comment "The client's job id — qBittorrent's infohash, SABnzbd's nzo_id — recorded at grab (`Acquisition.Grab`)"; rename in `observation_changeset/2`'s field list and `keep_existing/3`; `maybe_put_hash` gone (Task 7).

`queue_matcher.ex`: the moduledoc's "Matching rule" becomes one rule — by job id, case-insensitive; delete `find_by_title/3`, `find_exact/3`, `find_contained/3`, `@min_contain_len`, `normalized_for/1`, `normalize_title/1`; `find_item/3` is `find_item(queue, download_id, claimed \\ MapSet.new())` returning nil for a nil id; `row_pairing_keys/1` returns ids; `to_download/1` unchanged.

`pursuit_row.ex` VM: `:torrent_hash` → `:download_id`; `pairing_keys :: [String.t() | nil]`; drop `normalized_release_title`. `pursuits.ex` lines 673–734 and 804 follow. `observations.ex`: `QueueMatcher.find_item(queue, target.download_id)` and `download_id: item.id` in `record!/4` (write-once, so the grab's value stays). `snapshots.ex` line 81 likewise. `identity.ex`: rewrite the tier table — tier 1 is the job id for both protocols; the title tier is gone; `normalize_title/1` is deleted if nothing else calls it (`grep -rn "Identity.normalize_title" lib`).

`queue_item.ex`: delete `:normalized_title`, `normalize_title/1` and its comment; the `QueueItemTest` assertion that pinned the inlined normalisation goes too.

`targets.ex`: `in_flight_hashes/1` → `in_flight_download_ids/1`, `in_flight_hashes_for_unit/1` → `in_flight_download_ids_for_unit/1` (grep callers: `grep -rn in_flight_hashes lib test`); `cancel_for_download/2`'s doc drops the usenet paragraph — a usenet id is now carried.

`factory.ex` line 1399: `:download_id`.

- [ ] **Step 4: Run the tests**

Run: `~/scripts/agents/agent-mix ecto.migrate` is **not** run from this checkout against the dev database by hand — the test env migrates itself. Run: `~/scripts/agents/agent-mix test test/media_centaur/acquisition/ test/media_centaur/downloads/`
Expected: pass.

- [ ] **Step 5: Commit Tasks 7 and 8**

```bash
git add -A lib priv test
git commit -m "feat(acquisition): the app owns every grab — job id at grab time, pairing by id only"
```

---

### Task 9: Hand-off copy, showcase stub, docs, decision record, wiki

**Files:**
- Modify: `lib/media_centaur_web/components/acquisition/needs_attention.ex:184-190`, `test/media_centaur_web/components/acquisition/needs_attention_test.exs`
- Modify: `lib/media_centaur/showcase/stubs.ex:39-43` (drop the grab stub; add `{"POST", "/api/v2/torrents/add"}` → `"Ok."` to `qbittorrent_plug/1` only if `grep -rn "Grab.grab\|start_grabbing" lib/media_centaur/showcase` finds a showcase grab path; otherwise nothing)
- Modify: `docs/download-clients.md` (driver contract row for `add/3`; the "prowlarr-stack bootstrap contract" section: Prowlarr's download-client entries now serve Detect and Prowlarr's own UI only), `docs/architecture.md` (the Acquisition/Search boundary sentence), `lib/media_centaur/downloads/client_config.ex` and `search_result.ex` comments that say "Prowlarr routes each grab"
- Create: `decisions/architecture/2026-10-13-<NNN>-app-owned-grabs.md` (next NNN from `ls decisions/architecture | tail -1`), then `scripts/gen-decisions-index`
- Wiki: `Prowlarr-Integration.md`, `Download-Clients.md`, `Settings-Reference.md`

- [ ] **Step 1: Write the failing test**

In `needs_attention_test.exs`, the hand-off case:

```elixir
    test "the app cannot hand releases to the client → warning, points at the client's row in Settings" do
      card = NeedsAttention.client_card(@handoff_failed)

      assert card.severity == :warning
      assert card.title == "Can't hand releases to the download client"
      assert card.detail =~ "Settings → Acquisition"
      refute card.detail =~ "Prowlarr"
    end
```

- [ ] **Step 2: Run it to verify it fails**

Expected: title still names Prowlarr.

- [ ] **Step 3: Implement**

```elixir
  def client_card({:fault, :download_client_handoff_failed, _severity, _ids}) do
    %{
      title: "Can't hand releases to the download client",
      detail:
        "Grabs fail; each release is kept and retried every 15 minutes. Test the client under Settings → Acquisition.",
      severity: :warning
    }
  end
```

(Keep whatever other keys the existing map carries.)

Decision record, MADR 4.0, in the house style of the neighbouring records:

```markdown
# App-owned grabs: Prowlarr is search only

## Context and Problem Statement

Grabs went through Prowlarr's grab endpoint, which handed the release to Prowlarr's own download client and told the app nothing about the job. The app learned a usenet job's id only by matching the job's name to the release title on a later poll; while SABnzbd fetched the NZB the job was named after the URL (API key included), so it never matched and was shown as an unclaimed download that printed the key.

## Decision Outcome

The app submits every grab to the download client itself (`Acquisition.Grab`, `DownloadClient.add/3`) and records the client's job id on the target at grab time (`Target.download_id`). Pairing is by id only; title matching is retired. Each client slot carries the category the app files grabs under, seeded from Prowlarr's client config by Detect. Hand-off availability is written from the driver's own answer (`Downloads.HandoffAvailability`). Prowlarr's download-client entries serve Detect and Prowlarr's own UI; grabs made by the app do not appear in Prowlarr's history or statistics.

### Consequences

- A pursuit pairs with its job from the first poll, for both protocols; "never arrived" is exact.
- No client-side name, and no URL, ever reaches a view-model.
- Targets acquired before this change carry no id and do not pair; the file still imports through the watcher.
- Hand-off availability and `Downloads.Connectivity` now both measure the app's link to a client; folding the former into the latter is scheduled.
```

Wiki: in `Prowlarr-Integration.md`, the download-client setup section says Prowlarr's client entry is read by Detect from Prowlarr and used by Prowlarr's own interface; Media Centaur sends grabs to the client directly. In `Download-Clients.md`, add the Category field to each client's setup steps with the completed-folder consequence. In `Settings-Reference.md`, add the Category row under each client.

```sh
cd ~/src/media-centaur/media-centaur.wiki && git add -A && git commit -m "wiki: the app sends grabs to the download client; category per client" && git push
```

- [ ] **Step 4: Precommit**

Run: `~/scripts/agents/agent-mix precommit`
Expected: zero warnings, Boundary clean, all tests green.

- [ ] **Step 5: Commit**

```bash
git add -A lib docs decisions test
git commit -m "docs: ADR for app-owned grabs; hand-off copy names the app"
```

- [ ] **Step 6: CHANGELOG note for the next release**

Under the pending version in `CHANGELOG.md` (or wherever `/ship` drafts it): "Media Centaur now sends grabs to your download client itself. Each client has a Category in Settings → Acquisition (seeded by Detect from Prowlarr). Downloads that were in flight when you updated are not paired with their pursuit; they finish and import as before."

---

## Self-review

- **Spec coverage.** Identity at grab: Tasks 2, 6, 7. Column rename: Task 8. Title pairing retired: Task 8. Category field seeded by Detect: Tasks 3, 4. Both protocols direct: Task 2 (both drivers), Task 7 (one path). add-file transport: Task 2. Hand-off writer and probe from the driver: Task 5. Prowlarr history consequence: Task 9 ADR. Scheduled convergence named in the header.
- **Placeholders.** Test builders named as the files' own (`row/1`, `item/3`, `config`) are stated as such. The Boundary cycle check in Task 5 is a real decision point with both outcomes written.
- **Type consistency.** `DownloadClient.payload/0` shapes `{:nzb, bytes, name}`, `{:torrent, bytes}`, `{:magnet, uri}` across Tasks 1, 2, 6, 7; `add/3` returns `{:ok, id}`; `Grab.grab/1` returns `{:ok, id}`; `Grab.outage?/1`; `HandoffAvailability.observe/2` and `probe/0`; `Target.download_id`; `acquire_changeset/5` with a required id.
