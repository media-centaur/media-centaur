# Friends Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Nostr identity for this install — generated silently on first use, shown as an npub with a copy control, exportable and importable as an nsec — on a new Friends tab of the Discovery page.

**Architecture:** New bounded context `MediaCentaur.Friends` (`use Boundary, deps: [MediaCentaur.Nostr]`) with `Friends.Identity` over a new **sensitive** runtime config key `nostr_secret_key` (`Settings.Config` wraps it in `MediaCentaur.Secret` on write and on boot), typed events on a new `friends:updates` topic, and a context `subscribe/0` facade. `DiscoveryLive` becomes a two-action LiveView (`:watchlist`, `:friends`) via `handle_params/3`, GuideLive-shaped. The identity block is a function component under `lib/media_centaur_web/live/discovery_live/` (iterate-light: no story, no input-system nav yet).

**Tech Stack:** `MediaCentaur.Nostr.Keys` (layer 2), `Settings.Config`, `Topics`, LiveView, the existing `CopyButton` JS hook.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — decision 5 (key management), decision 11 (iterate light), Architecture › `MediaCentaur.Friends` (`Friends.Identity`, `friends:updates`), UI › Friends tab › Identity block. Layer 3 of the build order. Relays and the roster are layers 4 and 5.

**Decisions fixed by this plan:**
- Secret storage is a `Settings.Config` sensitive key (`:nostr_secret_key`, hex, default `nil`), not an ad-hoc settings entry: wrapped as `Secret` on runtime write and on the boot overlay for free.
- `Friends.Identity.ensure/0` generates on first call; the Friends tab calls it on mount of that action. Nothing else generates.
- Import replaces the identity with an inline two-click arm (Credo MC0027 treatment (b): costly but recoverable — the old nsec can be re-imported). No modal, no `data-confirm`.
- Export reveals the nsec inside a `<details>` disclosure with a plain warning and a Copy button (the `CopyButton` hook must not contain the nsec as its text — it swaps its label to "Copied!").
- Copy (house voice): tab label **Friends**; block heading **Your identity**; body line under the npub: **"Friends add you by this key. Your recommendations are visible to anyone who can read the relays you configure."**; disclosure summary **Secret key**; export text: **"This key is your identity. Anyone who has it can publish as you. Keep it somewhere safe; it is the only way to move this identity to another machine."**; export button **Show secret key** → reveals; import label **Import a secret key**, placeholder `nsec1…`, button **Replace identity** → armed **Click again to replace** ; success flash **Identity replaced**; error flash **That is not a valid secret key**.
- Route `/discovery/friends`, action `:friends`; `current_path` derived from the action.

**House rules:** test-first; zero warnings; `mix format`; MC0024 (selectors, not attribute substrings) in LiveView tests; MC0003 (`Friends.subscribe/0`, never `Phoenix.PubSub` from web); MC0025 (`Topics.publish/2` only, inside `Friends.Events`); MC0027 (no `data-confirm`); secrets never in logs or assigns (`Secret` stays wrapped; the LiveView holds the **npub** and, only while revealed, the nsec string — see Task 3); commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `lib/media_centaur/settings/config.ex` | `:nostr_secret_key` in `@runtime_settable_keys`, `@sensitive_keys`, `defaults`; public `sensitive_keys/0` |
| Modify | `lib/media_centaur/topics.ex` | `friends_updates/0` + moduledoc table row |
| Create | `lib/media_centaur/friends.ex` | Boundary anchor, `subscribe/0`, delegations |
| Create | `lib/media_centaur/friends/identity.ex` | `ensure/0`, `present?/0`, `pubkey/0`, `npub/0`, `export_nsec/0`, `import_nsec/1`, `secret/0` |
| Create | `lib/media_centaur/friends/events.ex` | `IdentityChanged` + `broadcast/1` |
| Modify | `lib/media_centaur_web.ex` | Boundary dep `MediaCentaur.Friends` |
| Modify | `lib/media_centaur_web/router.ex` | `live "/discovery/friends", DiscoveryLive, :friends` |
| Modify | `lib/media_centaur_web/live/discovery_live.ex` | `handle_params/3`, two panes, Friends tab, derived `current_path` |
| Create | `lib/media_centaur_web/live/discovery_live/identity_block.ex` | `identity_block/1` function component |
| Tests | `test/media_centaur/friends/identity_test.exs`, `test/media_centaur/settings/config_test.exs` (one assertion), `test/media_centaur_web/live/discovery_live_test.exs` | |

---

### Task 1: The sensitive config key

**Files:** `lib/media_centaur/settings/config.ex`, `test/media_centaur/settings/config_test.exs`

- [ ] **Step 1: Failing test** — add to `config_test.exs` (find the describe that checks `runtime_settable_keys/0`, ~line 189, and add next to it):

```elixir
  test "nostr_secret_key is runtime-settable, sensitive, and defaults to nil" do
    assert :nostr_secret_key in Config.runtime_settable_keys()
    assert :nostr_secret_key in Config.sensitive_keys()
    assert Config.defaults()[:nostr_secret_key] == nil
  end
```

(If `Config.defaults/0` is not public, assert via `Config.get(:nostr_secret_key) == nil` in the `config_update_test.exs` style instead — `use MediaCentaur.DataCase, async: false` with the `:persistent_term` snapshot/restore `setup` that file uses.) Run: fails on `sensitive_keys/0` undefined.

- [ ] **Step 2: Implement** — in `config.ex`: add `:nostr_secret_key` to `@sensitive_keys` (line ~55) and `@runtime_settable_keys` (~66), `nostr_secret_key: nil` to `defaults` (~427) with a comment `# Friends: this install's Nostr secret key (hex), generated on first use`; add

```elixir
  @doc "Keys whose values are wrapped in `MediaCentaur.Secret` (never logged or rendered)."
  @spec sensitive_keys() :: [atom()]
  def sensitive_keys, do: @sensitive_keys
```

next to `runtime_settable_keys/0`. The moduledoc at ~line 31 already names `sensitive_keys/0`.

- [ ] **Step 3:** `mix test test/media_centaur/settings && mix compile --warnings-as-errors && mix format` → commit `feat(settings): nostr_secret_key — a sensitive runtime config key for the Friends identity`.

---

### Task 2: `MediaCentaur.Friends` + `Identity` + events

**Files:** `lib/media_centaur/topics.ex`, `lib/media_centaur/friends.ex`, `lib/media_centaur/friends/identity.ex`, `lib/media_centaur/friends/events.ex`, `test/media_centaur/friends/identity_test.exs`

- [ ] **Step 1: Failing tests**

```elixir
defmodule MediaCentaur.Friends.IdentityTest do
  # Writes a Config key → :persistent_term; GlobalStateSandbox restores only for async: false.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Friends
  alias MediaCentaur.Friends.Events.IdentityChanged
  alias MediaCentaur.Friends.Identity
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings.Config

  @vector0_secret_hex String.duplicate("0", 63) <> "3"
  @vector0_pubkey_hex "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "ensure/0" do
    test "generates once and is stable afterwards" do
      refute Identity.present?()
      assert %Secret{} = Identity.ensure()
      assert Identity.present?()
      first = Identity.pubkey()
      assert %Secret{} = Identity.ensure()
      assert Identity.pubkey() == first
      assert Identity.npub() == Keys.to_npub(first)
    end

    test "broadcasts identity_changed only when it generates" do
      Friends.subscribe()
      Identity.ensure()
      assert_receive {:identity_changed, %IdentityChanged{pubkey: pubkey}}, 500
      assert pubkey == Identity.pubkey()
      Identity.ensure()
      refute_receive {:identity_changed, _}, 100
    end
  end

  describe "export_nsec/0 and import_nsec/1" do
    test "exports the current secret; import replaces it and broadcasts" do
      Identity.ensure()
      Friends.subscribe()

      nsec = Keys.to_nsec(Secret.wrap(@vector0_secret_hex))
      assert :ok = Identity.import_nsec(nsec)
      assert Identity.pubkey() == @vector0_pubkey_hex
      assert Identity.export_nsec() == nsec
      assert_receive {:identity_changed, %IdentityChanged{pubkey: @vector0_pubkey_hex}}, 500

      # stored wrapped, not bare
      assert %Secret{} = Config.get(:nostr_secret_key)
    end

    test "rejects an invalid nsec and keeps the identity" do
      Identity.ensure()
      before = Identity.pubkey()
      assert {:error, :invalid_secret} = Identity.import_nsec("nsec1nope")
      assert {:error, :invalid_secret} = Identity.import_nsec(Identity.npub())
      assert Identity.pubkey() == before
    end

    test "trims pasted whitespace" do
      Identity.ensure()
      nsec = Keys.to_nsec(Secret.wrap(@vector0_secret_hex))
      assert :ok = Identity.import_nsec("  " <> nsec <> "\n")
      assert Identity.pubkey() == @vector0_pubkey_hex
    end
  end

  test "pubkey/0, npub/0, export_nsec/0 are nil without an identity" do
    refute Identity.present?()
    assert Identity.pubkey() == nil
    assert Identity.npub() == nil
    assert Identity.export_nsec() == nil
  end
end
```

Verify the `Config` write is restored between tests: `test/support/global_state_sandbox.ex` restores `:persistent_term` for `async: false` tests, and `DataCase` rolls back the settings row. If the first test's `refute Identity.present?()` fails because a previous test's key survived, add a `setup` that snapshots/restores `:persistent_term.get({Config, :config})` exactly as `test/media_centaur/settings/config_update_test.exs:33-37` does.

- [ ] **Step 2: Topic** — `lib/media_centaur/topics.ex`: add `def friends_updates, do: "friends:updates"` beside `discovery_updates/0` and a row in the moduledoc topics table: `friends:updates` | `Friends.Events` (identity, and later relays/roster).

- [ ] **Step 3: Events** — `lib/media_centaur/friends/events.ex`, mirroring `lib/media_centaur/discovery/events.ex` exactly:

```elixir
defmodule MediaCentaur.Friends.Events do
  @moduledoc """
  Typed events on `friends:updates`. The only `Topics.publish` in the
  Friends context (event chokepoint).
  """

  alias MediaCentaur.Topics

  defmodule IdentityChanged do
    @moduledoc "The install's identity was generated or replaced."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  @type t :: IdentityChanged.t()

  @spec broadcast(t()) :: :ok
  def broadcast(%IdentityChanged{} = event), do: publish({:identity_changed, event})

  defp publish(message), do: Topics.publish(Topics.friends_updates(), message)
end
```

Check `discovery/events.ex` for the exact `publish/1` shape and whether a per-topic Credo contract check exists that needs registering (`ls credo_checks | grep contract` — if a `friends_updates_contract` is expected by convention, none exists; do not add one).

- [ ] **Step 4: Identity**

```elixir
defmodule MediaCentaur.Friends.Identity do
  @moduledoc """
  This install's Nostr identity: one secp256k1 keypair. The secret lives
  in the sensitive `nostr_secret_key` config key (hex, `MediaCentaur.Secret`
  wrapped at rest and in memory); the public key is derived on read.

  Generated on first use (`ensure/0`) — the Friends tab calls it when
  opened. Replaced only by `import_nsec/1`. Both broadcast
  `Friends.Events.IdentityChanged` so relay connections re-sign.
  """

  alias MediaCentaur.Friends.Events
  alias MediaCentaur.Friends.Events.IdentityChanged
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings.Config

  @key :nostr_secret_key

  @doc "The wrapped secret, generating and persisting one on first call."
  @spec ensure() :: Secret.t()
  def ensure do
    case secret() do
      %Secret{} = existing -> existing
      nil -> generate!()
    end
  end

  @doc "Whether an identity exists."
  @spec present?() :: boolean()
  def present?, do: Secret.present?(secret())

  @doc "The wrapped secret or nil."
  @spec secret() :: Secret.t() | nil
  def secret, do: Config.get(@key)

  @spec pubkey() :: String.t() | nil
  def pubkey do
    case secret() do
      %Secret{} = s -> Keys.pubkey(s)
      nil -> nil
    end
  end

  @spec npub() :: String.t() | nil
  def npub do
    case pubkey() do
      nil -> nil
      hex -> Keys.to_npub(hex)
    end
  end

  @spec export_nsec() :: String.t() | nil
  def export_nsec do
    case secret() do
      %Secret{} = s -> Keys.to_nsec(s)
      nil -> nil
    end
  end

  @doc "Replaces the identity with the pasted nsec (whitespace tolerated)."
  @spec import_nsec(String.t()) :: :ok | {:error, :invalid_secret}
  def import_nsec(nsec) when is_binary(nsec) do
    case Keys.from_nsec(String.trim(nsec)) do
      {:ok, %Secret{} = s} ->
        store!(s)
        :ok

      {:error, _} ->
        {:error, :invalid_secret}
    end
  end

  defp generate!, do: store!(Keys.generate())

  defp store!(%Secret{} = s) do
    {:ok, _} = Config.update(@key, Secret.expose(s))
    Events.broadcast(%IdentityChanged{pubkey: Keys.pubkey(s)})
    secret()
  end
end
```

Check `Config.update/2`'s return shape (`config.ex:237-252`) and adjust the match. `Config.update/2` also emits `{:setting_changed, "config:nostr_secret_key", %{"value" => hex}}` on `settings:updates` — grep every `handle_info({:setting_changed` in `lib/` and confirm none logs the value (report what you found).

- [ ] **Step 5: Context** — `lib/media_centaur/friends.ex`:

```elixir
defmodule MediaCentaur.Friends do
  use Boundary,
    deps: [MediaCentaur.Nostr],
    exports: [Identity, Events, Events.IdentityChanged]

  @moduledoc """
  Bounded context for the friend network's configuration: this install's
  identity (`Friends.Identity`) and, in later layers, the relay list and
  the friend roster. Broadcasts typed events on `friends:updates`;
  subscribe through `subscribe/0`.
  """

  alias MediaCentaur.Topics

  @doc "Subscribe the caller to friends events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.friends_updates())
end
```

`Settings.Config` is `top_level?: true, check: [in: false]`, so it needs no dep entry (confirm with `mix compile` — if Boundary complains, add `MediaCentaur.Settings`). Also add `MediaCentaur.Friends` to `lib/media_centaur_web.ex`'s Boundary `deps:` (needed by Task 3; add it now so the web compile stays clean).

- [ ] **Step 6:** `mix test test/media_centaur/friends test/media_centaur/settings && mix compile --warnings-as-errors && mix format && mix credo --strict` → commit `feat(friends): Identity — a Nostr keypair generated on first use, stored as a sensitive config key`.

---

### Task 3: Friends tab with the identity block

**Files:** `lib/media_centaur_web/router.ex`, `lib/media_centaur_web/live/discovery_live.ex`, `lib/media_centaur_web/live/discovery_live/identity_block.ex`, `test/media_centaur_web/live/discovery_live_test.exs`

- [ ] **Step 1: Failing tests** — add to `discovery_live_test.exs` (aliases `Friends.Identity`, `Nostr.Keys`, `Secret` as needed; keep `async: false`):

```elixir
  describe "friends tab — identity" do
    test "opening the tab generates an identity and shows the npub with a copy control", %{conn: conn} do
      refute Identity.present?()
      {:ok, view, _html} = live(conn, "/discovery/friends")

      assert Identity.present?()
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Friends")
      assert has_element?(view, "#identity-npub", Identity.npub())
      assert has_element?(view, "#copy-npub[data-copy-text='#{Identity.npub()}']")
      refute render(view) =~ Identity.export_nsec()
    end

    test "the secret key is revealed only on request", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      nsec = Identity.export_nsec()

      refute render(view) =~ nsec
      view |> element("#reveal-nsec") |> render_click()
      assert has_element?(view, "#identity-nsec", nsec)
      assert has_element?(view, "#copy-nsec[data-copy-text='#{nsec}']")
    end

    test "importing a secret key replaces the identity after a second click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      before = Identity.pubkey()
      nsec = Keys.to_nsec(Secret.wrap(String.duplicate("0", 63) <> "3"))

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert has_element?(view, "#import-nsec-submit", "Click again to replace")
      assert Identity.pubkey() == before

      view |> form("#import-nsec-form", %{"nsec" => nsec}) |> render_submit()
      assert Identity.pubkey() == "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
      assert render(view) =~ "Identity replaced"
      assert has_element?(view, "#identity-npub", Identity.npub())
    end

    test "an invalid secret key is refused with a flash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/friends")
      before = Identity.pubkey()

      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()
      view |> form("#import-nsec-form", %{"nsec" => "nsec1nope"}) |> render_submit()

      assert render(view) =~ "That is not a valid secret key"
      assert Identity.pubkey() == before
    end

    test "the watchlist tab still renders and the strip shows both tabs", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/discovery/watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a.zone-tab-active", "Watchlist")
      assert has_element?(view, "[data-nav-zone='zone-tabs'] a", "Friends")
    end
  end
```

Run: fails (no route).

- [ ] **Step 2: Route** — `router.ex`: `live "/discovery/friends", DiscoveryLive, :friends` after the watchlist route.

- [ ] **Step 3: `DiscoveryLive` becomes two-action**

- `mount/3`: keep subscriptions (`Discovery.subscribe()`, `Library.subscribe()`, add `Friends.subscribe()` under `connected?`), `page_title`, and `load_items/1`; add `assign(identity_npub: nil, nsec_revealed: nil, import_armed?: false)`.
- add:

```elixir
  @impl true
  def handle_params(_params, _uri, %{assigns: %{live_action: :friends}} = socket) do
    Identity.ensure()
    {:noreply, assign(socket, identity_npub: Identity.npub(), nsec_revealed: nil, import_armed?: false)}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}
```

- events:

```elixir
  def handle_event("reveal_nsec", _params, socket),
    do: {:noreply, assign(socket, nsec_revealed: Identity.export_nsec())}

  def handle_event("hide_nsec", _params, socket), do: {:noreply, assign(socket, nsec_revealed: nil)}

  # Two-click arm (MC0027 treatment b): the first submit arms, the second replaces.
  def handle_event("import_nsec", %{"nsec" => _}, %{assigns: %{import_armed?: false}} = socket),
    do: {:noreply, assign(socket, import_armed?: true)}

  def handle_event("import_nsec", %{"nsec" => nsec}, socket) do
    case Identity.import_nsec(nsec) do
      :ok ->
        {:noreply,
         socket
         |> assign(identity_npub: Identity.npub(), nsec_revealed: nil, import_armed?: false)
         |> put_flash(:info, "Identity replaced")}

      {:error, :invalid_secret} ->
        {:noreply, socket |> assign(import_armed?: false) |> put_flash(:error, "That is not a valid secret key")}
    end
  end
```

- `handle_info({:identity_changed, _}, socket)`: `{:noreply, assign(socket, identity_npub: Identity.npub())}` (another tab replaced it); keep the catch-all.
- `tabs/1` → both tabs: `%Tab{id: :watchlist, label: "Watchlist", navigate: "/discovery/watchlist", count: length(items)}` and `%Tab{id: :friends, label: "Friends", navigate: "/discovery/friends"}`.
- render: `active={@live_action}`, `current_path={current_path(@live_action)}` with `defp current_path(:friends), do: "/discovery/friends"` and `defp current_path(_), do: "/discovery/watchlist"`; the watchlist pane wrapped in `<div :if={@live_action == :watchlist} ...>` (keep its `data-nav-zone="grid"` and ids), and a friends pane:

```heex
          <div :if={@live_action == :friends} class="space-y-4">
            <IdentityBlock.identity_block
              npub={@identity_npub}
              nsec_revealed={@nsec_revealed}
              import_armed?={@import_armed?}
            />
          </div>
```

`data-nav-default-zone="discovery"` stays (layout key). The friends pane carries no nav zones in this iteration (decision 11).

- [ ] **Step 4: The identity block** — `lib/media_centaur_web/live/discovery_live/identity_block.ex`:

```elixir
defmodule MediaCentaurWeb.DiscoveryLive.IdentityBlock do
  @moduledoc """
  The Friends tab's identity block: this install's npub with a copy
  control, and a disclosure holding the secret key (reveal + copy) and
  the import form. Iteration-phase component (lives with the LiveView,
  no story yet — spec decision 11). Events bubble to `DiscoveryLive`:
  `reveal_nsec`, `hide_nsec`, `import_nsec`.
  """

  use MediaCentaurWeb, :html

  attr :npub, :string, required: true
  attr :nsec_revealed, :string, default: nil, doc: "the nsec while revealed; nil hides it"
  attr :import_armed?, :boolean, required: true

  def identity_block(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4" data-component="identity-block">
      <div class="space-y-1">
        <h2 class="text-sm font-semibold">Your identity</h2>
        <p class="text-xs text-base-content/50">
          Friends add you by this key. Your recommendations are visible to anyone who can read the relays you configure.
        </p>
      </div>

      <div class="flex items-center gap-3">
        <code id="identity-npub" class="min-w-0 flex-1 truncate rounded-md bg-base-content/5 px-3 py-2 text-xs">{@npub}</code>
        <.button id="copy-npub" variant="dismiss" size="xs" class="shrink-0" phx-hook="CopyButton" data-copy-text={@npub}>
          Copy
        </.button>
      </div>

      <details class="release-notes-disclosure">
        <summary class="cursor-pointer select-none text-xs text-base-content/50">
          <.icon name="hero-chevron-right-mini" class="disclosure-caret size-3.5" /> Secret key
        </summary>
        <div class="mt-3 ml-5 space-y-4 border-l border-base-content/10 pl-4 text-sm">
          <p class="text-xs text-base-content/60">
            This key is your identity. Anyone who has it can publish as you. Keep it somewhere safe; it is the only way to move this identity to another machine.
          </p>

          <div :if={is_nil(@nsec_revealed)}>
            <.button id="reveal-nsec" variant="neutral" size="sm" phx-click="reveal_nsec">Show secret key</.button>
          </div>
          <div :if={@nsec_revealed} class="flex items-center gap-3">
            <code id="identity-nsec" class="min-w-0 flex-1 truncate rounded-md bg-base-content/5 px-3 py-2 text-xs">{@nsec_revealed}</code>
            <.button id="copy-nsec" variant="dismiss" size="xs" class="shrink-0" phx-hook="CopyButton" data-copy-text={@nsec_revealed}>
              Copy
            </.button>
            <.button variant="dismiss" size="xs" class="shrink-0" phx-click="hide_nsec">Hide</.button>
          </div>

          <form id="import-nsec-form" phx-submit="import_nsec" class="space-y-2">
            <label for="import-nsec" class="block text-xs font-medium">Import a secret key</label>
            <textarea id="import-nsec" name="nsec" rows="2" placeholder="nsec1…" class="textarea textarea-bordered w-full font-mono text-xs"></textarea>
            <.button id="import-nsec-submit" type="submit" variant={if @import_armed?, do: "danger", else: "neutral"} size="sm">
              {if @import_armed?, do: "Click again to replace", else: "Replace identity"}
            </.button>
          </form>
        </div>
      </details>
    </section>
    """
  end
end
```

Check `CoreComponents.button/1`'s accepted `variant` values and the `disclosure-caret` / `release-notes-disclosure` classes exist (`grep -n "release-notes-disclosure\|disclosure-caret" assets/css/app.css`); use what exists. The `CopyButton` hook replaces the button's text with "Copied!" — the nsec is in the `<code>`, not the button, as required. The `textarea` must not re-render with the pasted value on the armed re-render (LiveView leaves a focused input's value alone; an unfocused one keeps its DOM value since the template has no value binding) — the second submit therefore resubmits the same text; the test submits the value explicitly either way.

- [ ] **Step 5: Verify** — `mix format && mix compile --warnings-as-errors && mix test test/media_centaur_web/live/discovery_live_test.exs test/media_centaur_web/page_smoke_test.exs test/media_centaur_web/no_db_on_render_test.exs && mix credo --strict && mix boundaries`. Add `{"/discovery/friends", "discovery friends"}` to `page_smoke_test.exs`. Then a real-browser check: `~/scripts/agents/page-shot --url http://127.0.0.1:2160/discovery/friends --viewport 1920x1080 --wait-ms 3000` and Read the PNG — heading, both tabs with Friends active, the identity block with an npub and Copy. (This generates the owner's real identity on the dev database — intended; it is the same as the owner opening the tab.)

- [ ] **Step 6:** commit `feat(discovery): Friends tab — identity block (npub, secret key export/import)`.

---

### Task 4: Precommit + campaign

- [ ] `mix precommit` PASSED.
- [ ] `campaigns/friends-recommendations.md` Status: "Layer 3 (Friends identity: `Friends.Identity` on the sensitive `nostr_secret_key` config key, Friends tab identity block at `/discovery/friends`) landed 2026-09-02; next: layer 4 (`Nostr.Connection` + fake relay + `Friends.Relay` + relay block)." Next steps: add "**Wiki (layer 8):** Friends-and-Recommendations page must carry the backup advice for the secret key."
- [ ] Commit `docs(campaign): Friends identity landed; next = relay connections`.

---

## Self-review

**Spec coverage:** decision 5 (generate silently on first open; npub + copy; export/import behind a disclosure; no passphrase) → Tasks 2–3. `Friends.Identity` API (`ensure/0`, `npub/0`, `export_nsec/0`, `import_nsec/1`, `identity_changed` broadcast) → Task 2. Sensitive Settings key → Task 1. `friends:updates` → Task 2. Friends tab at `/discovery/friends`, iterate-light component placement → Task 3. Relays/roster blocks → layers 4–5.

**Type consistency:** `Identity.ensure/0 :: Secret.t()`, `present?/0`, `secret/0`, `pubkey/0`, `npub/0`, `export_nsec/0`, `import_nsec/1 :: :ok | {:error, :invalid_secret}`; `Friends.subscribe/0`; `Events.IdentityChanged{pubkey}` under `{:identity_changed, event}`; LiveView assigns `identity_npub`, `nsec_revealed`, `import_armed?`; events `reveal_nsec`, `hide_nsec`, `import_nsec`; element ids `identity-npub`, `copy-npub`, `reveal-nsec`, `identity-nsec`, `copy-nsec`, `import-nsec-form`, `import-nsec`, `import-nsec-submit`.

**Placeholders:** none.
