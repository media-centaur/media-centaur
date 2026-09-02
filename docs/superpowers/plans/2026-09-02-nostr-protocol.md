# Nostr Protocol Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `MediaCentaur.Nostr` — keys (secp256k1 keypair, npub/nsec), events (NIP-01 canonical serialization, id, BIP-340 sign/verify, JSON wire form), and subscription filters — as a pure protocol library with no domain knowledge and no network.

**Architecture:** Three modules under `lib/media_centaur/nostr/`, `use Boundary, deps: [], exports: [Keys, Event, Filter]`. Crypto via `bitcoinex` (pure Elixir): `PrivateKey`/`Point`/`Schnorr` for keys and signatures, `Bech32` for NIP-19. Secret keys are `MediaCentaur.Secret`-wrapped hex everywhere except the signing call. The event id is computed from our own canonical serializer (not `Jason`) so the bytes match reference clients for every input. The relay connection (`Nostr.Connection`) is the next layer and is **not** in this plan.

**Tech Stack:** Elixir, `bitcoinex ~> 0.3` (new dep), `:crypto`, `Jason`. No NIF.

**Spec:** `docs/superpowers/specs/2026-09-02-friends-recommendations-design.md` — Architecture › `MediaCentaur.Nostr` (`Keys`, `Event`, `Filter`); decisions 9 (no NIF, bitcoinex) and 10 (thin in-house client). Layer 2 of the build order.

**Research findings this plan is built on** (verified against bitcoinex 0.3.0 source, 2026-09-02):
- `Bitcoinex.Secp256k1.PrivateKey.new/1` takes an **integer**; its validation accepts `d == 0` — we guard `1 <= d < n` ourselves.
- `Point.x_bytes/1` is the 32-byte x-only pubkey; `Point.lift_x/1` (32-byte binary) parses it back. Never use `sec/1`/`serialize_public_key/1` (33-byte compressed) for Nostr.
- `Schnorr.sign(privkey, z_int, aux_int)` → `{:ok, %Signature{r, s}}`; `Schnorr.verify_signature(point, z_int, sig)` → `true | false | {:error, _}`. `z` and `aux` are integers.
- **`Signature.serialize_signature/1` is unsafe** (no zero-padding, ~0.8 % of signatures come out short). Serialize as `<<r::big-unsigned-256, s::big-unsigned-256>>`. `Signature.parse_signature/1` (exactly 64 bytes) is fine.
- `Bech32.encode(hrp, five_bit_list, :bech32)` / `Bech32.decode(str)` → `{:ok, {:bech32, hrp, five_bit_list}}`; `Bech32.convert_bits(list, 8, 5, true)` and `(list, 5, 8, false)` do the byte↔5-bit conversion. Encoding is `:bech32`, not `:bech32m`.
- BIP-340 vectors ship in bitcoinex's own tests (`test/secp256k1/schnorr_test.exs` in the hex tarball) — copy vector 0 from there.
- `Jason.encode!/1` matches NIP-01 serialization for all content except C0 controls other than `\b \t \n \f \r` (Jason emits uppercase ``; reference clients emit lowercase). Hence the custom escaper below.

**House rules:** test-first; zero warnings; `mix format`; no real names in fixtures; secrets never in logs (`MediaCentaur.Secret`); commits end with `Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz`, never `Co-Authored-By`; no push, no tag.

---

## File map

| Action | Path | Responsibility |
|---|---|---|
| Modify | `mix.exs` | add `{:bitcoinex, "~> 0.3"}` |
| Create | `lib/media_centaur/nostr.ex` | Boundary anchor + moduledoc |
| Create | `lib/media_centaur/nostr/keys.ex` | generate, derive pubkey, npub/nsec, hex helpers |
| Create | `lib/media_centaur/nostr/event.ex` | struct, canonical serialization, id, sign, verify, JSON in/out |
| Create | `lib/media_centaur/nostr/filter.ex` | subscription filter builder |
| Create | `test/media_centaur/nostr/keys_test.exs`, `event_test.exs`, `filter_test.exs` | |

---

### Task 1: Dependency + `Nostr.Keys`

**Files:** `mix.exs`, `lib/media_centaur/nostr.ex`, `lib/media_centaur/nostr/keys.ex`, `test/media_centaur/nostr/keys_test.exs`

- [ ] **Step 1: Add the dependency**

In `mix.exs` deps add `{:bitcoinex, "~> 0.3"}` (alphabetical position). Run `mix deps.get` and `mix compile`. `mix deps.audit` must stay clean (precommit checks it).

- [ ] **Step 2: Write the failing tests**

```elixir
defmodule MediaCentaur.Nostr.KeysTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret

  # BIP-340 test vector 0 (bitcoin/bips bip-0340/test-vectors.csv):
  # secret key 3, its x-only public key.
  @vector0_secret_hex String.duplicate("0", 63) <> "3"
  @vector0_pubkey_hex "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  describe "generate/0" do
    test "returns a wrapped 64-hex secret whose pubkey derives deterministically" do
      secret = Keys.generate()
      assert %Secret{} = secret
      assert Secret.expose(secret) =~ ~r/^[0-9a-f]{64}$/
      assert Keys.pubkey(secret) == Keys.pubkey(secret)
      assert Keys.pubkey(secret) =~ ~r/^[0-9a-f]{64}$/
    end

    test "two generations differ" do
      refute Secret.expose(Keys.generate()) == Secret.expose(Keys.generate())
    end
  end

  describe "pubkey/1" do
    test "derives the x-only public key of BIP-340 vector 0" do
      assert Keys.pubkey(Secret.wrap(@vector0_secret_hex)) == @vector0_pubkey_hex
    end
  end

  describe "valid_secret?/1" do
    test "rejects zero, the curve order, non-hex, and wrong length" do
      refute Keys.valid_secret?(String.duplicate("0", 64))
      refute Keys.valid_secret?("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141")
      refute Keys.valid_secret?("zz")
      refute Keys.valid_secret?(String.duplicate("a", 63))
      assert Keys.valid_secret?(@vector0_secret_hex)
      assert Keys.valid_secret?("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140")
    end
  end

  describe "npub / nsec" do
    test "round-trips the secret through nsec" do
      secret = Secret.wrap(@vector0_secret_hex)
      nsec = Keys.to_nsec(secret)
      assert String.starts_with?(nsec, "nsec1")
      assert String.length(nsec) == 63
      assert {:ok, back} = Keys.from_nsec(nsec)
      assert Secret.expose(back) == @vector0_secret_hex
    end

    test "round-trips the pubkey through npub" do
      npub = Keys.to_npub(@vector0_pubkey_hex)
      assert String.starts_with?(npub, "npub1")
      assert String.length(npub) == 63
      assert Keys.from_npub(npub) == {:ok, @vector0_pubkey_hex}
    end

    test "rejects the wrong prefix, a bad checksum, and garbage" do
      npub = Keys.to_npub(@vector0_pubkey_hex)
      assert {:error, _} = Keys.from_nsec(npub)
      assert {:error, _} = Keys.from_npub(Keys.to_nsec(Secret.wrap(@vector0_secret_hex)))
      assert {:error, _} = Keys.from_npub(String.slice(npub, 0..-2//1) <> "x")
      assert {:error, _} = Keys.from_npub("hello")
    end
  end

  describe "parse_pubkey/1" do
    test "accepts an npub or 64-hex and normalizes to lowercase hex" do
      npub = Keys.to_npub(@vector0_pubkey_hex)
      assert Keys.parse_pubkey(npub) == {:ok, @vector0_pubkey_hex}
      assert Keys.parse_pubkey(String.upcase(@vector0_pubkey_hex)) == {:ok, @vector0_pubkey_hex}
      assert {:error, _} = Keys.parse_pubkey("npub1notreal")
      assert {:error, _} = Keys.parse_pubkey("12")
    end
  end
end
```

Confirm the vector-0 values against the copy in the bitcoinex tarball tests (`curl -sL https://repo.hex.pm/tarballs/bitcoinex-0.3.0.tar` → `contents.tar.gz` → `test/secp256k1/schnorr_test.exs`, first entry of `@schnorr_signatures_with_secrets`); if they differ from the constants above, the tarball wins — fix the constants.

Run: `mix test test/media_centaur/nostr/keys_test.exs` — expected: module undefined.

- [ ] **Step 3: Boundary anchor**

`lib/media_centaur/nostr.ex`:

```elixir
defmodule MediaCentaur.Nostr do
  use Boundary, deps: [], exports: [Event, Filter, Keys]

  @moduledoc """
  Nostr protocol, nothing else: keys (`Keys`), events (`Event`) and
  subscription filters (`Filter`). Pure functions over binaries and
  maps — no persistence, no network, no knowledge of what an event
  means. The relay connection process lives beside these
  (`Connection`, next layer); the recommendations domain that gives
  events meaning is `MediaCentaur.Recommendations`.

  Crypto is `bitcoinex` (pure Elixir): secp256k1 keys, BIP-340 Schnorr
  signatures, bech32 for NIP-19. Secret keys are `MediaCentaur.Secret`
  everywhere except the signing call.
  """
end
```

- [ ] **Step 4: `Keys`**

`lib/media_centaur/nostr/keys.ex`:

```elixir
defmodule MediaCentaur.Nostr.Keys do
  @moduledoc """
  secp256k1 keypairs as Nostr uses them: a 32-byte secret, its x-only
  32-byte public key (BIP-340), and the NIP-19 bech32 forms `nsec` /
  `npub`. In-app representation is lowercase hex; the secret rides in
  `MediaCentaur.Secret` and is exposed only inside `pubkey/1` and the
  signing call in `Event`.

  `bitcoinex` accepts a zero scalar as a private key; we do not
  (`valid_secret?/1` enforces `1 <= d < n`).
  """

  alias Bitcoinex.Bech32
  alias Bitcoinex.Secp256k1.{Point, PrivateKey}
  alias MediaCentaur.Secret

  # secp256k1 group order n (BIP-340).
  @n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  @type hex32 :: String.t()

  @doc "A fresh random secret key, wrapped."
  @spec generate() :: Secret.t()
  def generate do
    d = :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
    if d >= 1 and d < @n, do: Secret.wrap(hex32(d)), else: generate()
  end

  @doc "Whether `hex` is a well-formed secret: 64 hex chars, `1 <= d < n`."
  @spec valid_secret?(term()) :: boolean()
  def valid_secret?(hex) when is_binary(hex) do
    case parse_hex32(hex) do
      {:ok, d} -> d >= 1 and d < @n
      :error -> false
    end
  end

  def valid_secret?(_other), do: false

  @doc "The x-only public key (lowercase hex) of a wrapped secret."
  @spec pubkey(Secret.t()) :: hex32()
  def pubkey(%Secret{} = secret) do
    secret |> private_key!() |> PrivateKey.to_point() |> Point.x_hex()
  end

  @doc false
  @spec private_key!(Secret.t()) :: PrivateKey.t()
  def private_key!(%Secret{} = secret) do
    hex = Secret.expose(secret)

    with true <- valid_secret?(hex),
         {:ok, d} <- parse_hex32(hex),
         {:ok, key} <- PrivateKey.new(d) do
      key
    else
      _ -> raise ArgumentError, "invalid Nostr secret key"
    end
  end

  @doc "Parse an x-only public key from `npub…` or 64-hex into lowercase hex."
  @spec parse_pubkey(String.t()) :: {:ok, hex32()} | {:error, :invalid_pubkey}
  def parse_pubkey("npub1" <> _ = npub), do: from_npub(npub)

  def parse_pubkey(hex) when is_binary(hex) do
    case parse_hex32(hex) do
      {:ok, x} -> if lift_x_ok?(x), do: {:ok, String.downcase(hex)}, else: {:error, :invalid_pubkey}
      :error -> {:error, :invalid_pubkey}
    end
  end

  def parse_pubkey(_other), do: {:error, :invalid_pubkey}

  @spec to_npub(hex32()) :: String.t()
  def to_npub(pubkey_hex), do: bech32_encode!("npub", Base.decode16!(pubkey_hex, case: :mixed))

  @spec from_npub(String.t()) :: {:ok, hex32()} | {:error, :invalid_pubkey}
  def from_npub(npub) do
    case bech32_decode(npub, "npub") do
      {:ok, <<_::binary-32>> = bytes} ->
        hex = Base.encode16(bytes, case: :lower)
        parse_pubkey(hex)

      _ ->
        {:error, :invalid_pubkey}
    end
  end

  @spec to_nsec(Secret.t()) :: String.t()
  def to_nsec(%Secret{} = secret),
    do: bech32_encode!("nsec", Base.decode16!(Secret.expose(secret), case: :mixed))

  @spec from_nsec(String.t()) :: {:ok, Secret.t()} | {:error, :invalid_secret}
  def from_nsec(nsec) do
    with {:ok, <<_::binary-32>> = bytes} <- bech32_decode(nsec, "nsec"),
         hex = Base.encode16(bytes, case: :lower),
         true <- valid_secret?(hex) do
      {:ok, Secret.wrap(hex)}
    else
      _ -> {:error, :invalid_secret}
    end
  end

  # --- helpers ---

  defp hex32(int), do: int |> :binary.encode_unsigned() |> pad32() |> Base.encode16(case: :lower)

  defp pad32(bin) when byte_size(bin) < 32, do: :binary.copy(<<0>>, 32 - byte_size(bin)) <> bin
  defp pad32(bin), do: bin

  defp parse_hex32(hex) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, :binary.decode_unsigned(bytes)}
      :error -> :error
    end
  end

  defp parse_hex32(_other), do: :error

  defp lift_x_ok?(x), do: match?({:ok, _}, Point.lift_x(x))

  defp bech32_encode!(hrp, <<_::binary-32>> = bytes) do
    {:ok, five} = Bech32.convert_bits(:binary.bin_to_list(bytes), 8, 5, true)
    {:ok, encoded} = Bech32.encode(hrp, five, :bech32)
    encoded
  end

  defp bech32_decode(str, expected_hrp) when is_binary(str) do
    with {:ok, {:bech32, ^expected_hrp, five}} <- Bech32.decode(str),
         {:ok, bytes} <- Bech32.convert_bits(five, 5, 8, false) do
      {:ok, :binary.list_to_bin(bytes)}
    else
      _ -> :error
    end
  end

  defp bech32_decode(_other, _hrp), do: :error
end
```

Check each bitcoinex call against the source (`deps/bitcoinex/lib/...`) — `Point.x_hex/1`, `Point.lift_x/1` (integer clause), `Bech32.decode/1` return shape, `convert_bits/4` — and adjust if a shape differs. `Bech32.decode/1` lowercases? bech32 is case-insensitive; if it rejects uppercase, `String.downcase/1` first.

- [ ] **Step 5: Run, format, commit**

`mix test test/media_centaur/nostr/keys_test.exs && mix compile --warnings-as-errors && mix format && mix credo --strict lib/media_centaur/nostr lib/media_centaur/nostr.ex`

```bash
git add mix.exs mix.lock lib/media_centaur/nostr.ex lib/media_centaur/nostr/keys.ex test/media_centaur/nostr/keys_test.exs
git commit -m "feat(nostr): Keys — secp256k1 keypairs, npub/nsec (bitcoinex, no NIF)

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 2: `Nostr.Event` — serialization, id, sign, verify, JSON

**Files:** `lib/media_centaur/nostr/event.ex`, `test/media_centaur/nostr/event_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule MediaCentaur.Nostr.EventTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.{Event, Keys}
  alias MediaCentaur.Secret

  @secret Secret.wrap(String.duplicate("0", 63) <> "3")
  @pubkey "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"

  defp unsigned(overrides \\ %{}) do
    Event.new(
      Map.merge(
        %{pubkey: @pubkey, created_at: 1_700_000_000, kind: 1, tags: [["d", "sample"]], content: "hello"},
        overrides
      )
    )
  end

  describe "serialize/1 (NIP-01 canonical form)" do
    test "is the compact JSON array [0, pubkey, created_at, kind, tags, content]" do
      assert Event.serialize(unsigned()) ==
               ~s([0,"#{@pubkey}",1700000000,1,[["d","sample"]],"hello"])
    end

    test "escapes exactly the NIP-01 set and leaves UTF-8 verbatim" do
      content = "q\"b\\n\nr\rt\tb\bf\fé😀/"
      serialized = Event.serialize(unsigned(%{content: content}))
      assert String.ends_with?(serialized, ~s(,"q\\"b\\\\n\\nr\\rt\\tb\\bf\\fé😀/"]))
    end

    test "other control characters become lowercase \\u00xx like JSON.stringify" do
      serialized = Event.serialize(unsigned(%{content: <<1, 0x1F>>}))
      assert String.ends_with?(serialized, ~s(,"\\u0001\\u001f"]))
    end

    test "agrees with Jason for ordinary content" do
      event = unsigned(%{content: "plain text — with punctuation, quotes \" and slashes /", tags: [["p", "x"], ["t", "a b"]]})
      assert Event.serialize(event) ==
               Jason.encode!([0, event.pubkey, event.created_at, event.kind, event.tags, event.content])
    end
  end

  describe "id/1" do
    test "is the lowercase sha256 hex of the serialization" do
      event = unsigned()
      expected = :crypto.hash(:sha256, Event.serialize(event)) |> Base.encode16(case: :lower)
      assert Event.id(event) == expected
    end
  end

  describe "sign/2 and verify/1" do
    test "signs with the secret, sets pubkey/id/sig, and verifies" do
      event = Event.new(%{created_at: 1_700_000_000, kind: 1, tags: [], content: "hello"})
      signed = Event.sign(event, @secret)

      assert signed.pubkey == @pubkey
      assert signed.id == Event.id(signed)
      assert signed.sig =~ ~r/^[0-9a-f]{128}$/
      assert Event.verify(signed) == :ok
    end

    test "a signature is always 64 bytes even when r or s has leading zeros" do
      # Sign many events; every sig must be exactly 128 hex chars.
      for i <- 1..64 do
        signed = Event.sign(Event.new(%{created_at: i, kind: 1, tags: [], content: "n#{i}"}), @secret)
        assert byte_size(signed.sig) == 128
        assert Event.verify(signed) == :ok
      end
    end

    test "verify rejects a tampered id, a tampered content, a wrong signature, and a malformed event" do
      signed = Event.sign(Event.new(%{created_at: 1, kind: 1, tags: [], content: "hello"}), @secret)

      assert Event.verify(%{signed | id: String.duplicate("0", 64)}) == {:error, :bad_id}
      assert Event.verify(%{signed | content: "bye"}) == {:error, :bad_id}
      assert Event.verify(%{signed | sig: String.duplicate("0", 128)}) == {:error, :bad_signature}
      assert Event.verify(%{signed | sig: "zz"}) == {:error, :malformed}
      assert Event.verify(%{signed | pubkey: "not-hex"}) == {:error, :malformed}
    end

    test "verify rejects a signature made by a different key" do
      other = Keys.generate()
      signed = Event.sign(Event.new(%{created_at: 1, kind: 1, tags: [], content: "hello"}), other)
      forged = %{signed | pubkey: @pubkey, id: Event.id(%{signed | pubkey: @pubkey})}
      assert Event.verify(forged) == {:error, :bad_signature}
    end
  end

  describe "to_map/1 and from_map/1 (wire form)" do
    test "round-trips through JSON" do
      signed = Event.sign(Event.new(%{created_at: 1, kind: 32160, tags: [["d", "tmdb:movie:603"]], content: "{}"}), @secret)
      json = signed |> Event.to_map() |> Jason.encode!()

      assert {:ok, decoded} = json |> Jason.decode!() |> Event.from_map()
      assert decoded == signed
      assert Event.verify(decoded) == :ok
    end

    test "from_map rejects wrong shapes" do
      assert {:error, :malformed} = Event.from_map(%{"id" => 1})
      assert {:error, :malformed} = Event.from_map(%{"id" => "a", "pubkey" => "b", "created_at" => "x", "kind" => 1, "tags" => [], "content" => "", "sig" => "c"})
      assert {:error, :malformed} = Event.from_map(%{"id" => "a", "pubkey" => "b", "created_at" => 1, "kind" => 1, "tags" => [["ok"], "notalist"], "content" => "", "sig" => "c"})
      assert {:error, :malformed} = Event.from_map("nope")
    end
  end

  describe "tag helpers" do
    test "tag_value/2 returns the first value of the first matching tag" do
      event = unsigned(%{tags: [["d", "one"], ["p", "pk"], ["d", "two"]]})
      assert Event.tag_value(event, "d") == "one"
      assert Event.tag_value(event, "p") == "pk"
      assert Event.tag_value(event, "e") == nil
    end
  end
end
```

Run: `mix test test/media_centaur/nostr/event_test.exs` — expected: module undefined.

- [ ] **Step 2: `Event`**

`lib/media_centaur/nostr/event.ex`:

```elixir
defmodule MediaCentaur.Nostr.Event do
  @moduledoc """
  A NIP-01 event: the signed unit of everything Nostr carries.

      %Event{id, pubkey, created_at, kind, tags, content, sig}

  `id` is the lowercase sha256 hex of the canonical serialization
  `[0, pubkey, created_at, kind, tags, content]` — compact JSON with
  NIP-01's escaping rules, which `serialize/1` implements itself rather
  than via `Jason`: the reference clients escape the rare control
  characters as lowercase `\\u00xx`, `Jason` as uppercase, and a
  one-byte difference is a different id and a rejected signature.
  `sig` is the 64-byte BIP-340 Schnorr signature over the id, hex.

  Construction: `new/1` (unsigned, pubkey optional) → `sign/2` fills
  `pubkey`, `id` and `sig`. Inbound: `from_map/1` (wire JSON, shape-
  checked) → `verify/1` (id recomputed, signature checked). Both
  directions are pure; nothing here knows what a kind means.
  """

  alias Bitcoinex.Secp256k1.{Point, Schnorr, Signature}
  alias MediaCentaur.Nostr.Keys
  alias MediaCentaur.Secret

  @enforce_keys [:created_at, :kind, :tags, :content]
  defstruct [:id, :pubkey, :created_at, :kind, :tags, :content, :sig]

  @type tag :: [String.t()]
  @type t :: %__MODULE__{
          id: String.t() | nil,
          pubkey: String.t() | nil,
          created_at: non_neg_integer(),
          kind: non_neg_integer(),
          tags: [tag()],
          content: String.t(),
          sig: String.t() | nil
        }

  @doc "An unsigned event from `created_at`, `kind`, `tags`, `content` (and optionally `pubkey`)."
  @spec new(map()) :: t()
  def new(attrs) do
    %__MODULE__{
      pubkey: attrs[:pubkey],
      created_at: Map.fetch!(attrs, :created_at),
      kind: Map.fetch!(attrs, :kind),
      tags: Map.get(attrs, :tags, []),
      content: Map.get(attrs, :content, "")
    }
  end

  @doc "NIP-01 canonical serialization — the exact bytes the id hashes."
  @spec serialize(t()) :: String.t()
  def serialize(%__MODULE__{} = event) do
    tags =
      event.tags
      |> Enum.map(fn tag -> "[" <> Enum.map_join(tag, ",", &json_string/1) <> "]" end)
      |> Enum.join(",")

    "[0," <>
      json_string(event.pubkey) <>
      "," <>
      Integer.to_string(event.created_at) <>
      "," <>
      Integer.to_string(event.kind) <>
      ",[" <> tags <> "]," <> json_string(event.content) <> "]"
  end

  @doc "The event id: lowercase sha256 hex of `serialize/1`."
  @spec id(t()) :: String.t()
  def id(%__MODULE__{} = event),
    do: :crypto.hash(:sha256, serialize(event)) |> Base.encode16(case: :lower)

  @doc "Sets `pubkey` from the secret, computes `id`, signs it (BIP-340)."
  @spec sign(t(), Secret.t()) :: t()
  def sign(%__MODULE__{} = event, %Secret{} = secret) do
    event = %{event | pubkey: Keys.pubkey(secret)}
    id = id(event)
    z = id |> Base.decode16!(case: :lower) |> :binary.decode_unsigned()
    aux = :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
    {:ok, %Signature{r: r, s: s}} = Schnorr.sign(Keys.private_key!(secret), z, aux)
    # bitcoinex's own serializer does not zero-pad r/s; fixed-width here.
    sig = Base.encode16(<<r::big-unsigned-256, s::big-unsigned-256>>, case: :lower)
    %{event | id: id, sig: sig}
  end

  @doc """
  Recomputes the id and checks the signature against `pubkey`.
  `{:error, :malformed}` when a hex field is not the right shape.
  """
  @spec verify(t()) :: :ok | {:error, :bad_id | :bad_signature | :malformed}
  def verify(%__MODULE__{} = event) do
    with {:ok, pubkey_bytes} <- decode_hex(event.pubkey, 32),
         {:ok, id_bytes} <- decode_hex(event.id, 32),
         {:ok, sig_bytes} <- decode_hex(event.sig, 64),
         :ok <- check_id(event),
         :ok <- check_signature(pubkey_bytes, id_bytes, sig_bytes) do
      :ok
    end
  end

  @doc "The wire map (string keys) a relay accepts inside `[\"EVENT\", ...]`."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      "id" => event.id,
      "pubkey" => event.pubkey,
      "created_at" => event.created_at,
      "kind" => event.kind,
      "tags" => event.tags,
      "content" => event.content,
      "sig" => event.sig
    }
  end

  @doc "Parses a decoded wire map; shape only — call `verify/1` afterwards."
  @spec from_map(term()) :: {:ok, t()} | {:error, :malformed}
  def from_map(%{
        "id" => id,
        "pubkey" => pubkey,
        "created_at" => created_at,
        "kind" => kind,
        "tags" => tags,
        "content" => content,
        "sig" => sig
      })
      when is_binary(id) and is_binary(pubkey) and is_integer(created_at) and created_at >= 0 and
             is_integer(kind) and kind >= 0 and is_list(tags) and is_binary(content) and is_binary(sig) do
    if Enum.all?(tags, &(is_list(&1) and Enum.all?(&1, fn v -> is_binary(v) end))) do
      {:ok, %__MODULE__{id: id, pubkey: pubkey, created_at: created_at, kind: kind, tags: tags, content: content, sig: sig}}
    else
      {:error, :malformed}
    end
  end

  def from_map(_other), do: {:error, :malformed}

  @doc "The first value of the first tag named `name`, or nil."
  @spec tag_value(t(), String.t()) :: String.t() | nil
  def tag_value(%__MODULE__{tags: tags}, name) do
    Enum.find_value(tags, fn
      [^name, value | _rest] -> value
      _other -> nil
    end)
  end

  # --- verification ---

  defp check_id(event) do
    if id(event) == event.id, do: :ok, else: {:error, :bad_id}
  end

  defp check_signature(pubkey_bytes, id_bytes, sig_bytes) do
    with {:ok, point} <- Point.lift_x(pubkey_bytes),
         {:ok, signature} <- Signature.parse_signature(sig_bytes) do
      case Schnorr.verify_signature(point, :binary.decode_unsigned(id_bytes), signature) do
        true -> :ok
        _false_or_error -> {:error, :bad_signature}
      end
    else
      _ -> {:error, :bad_signature}
    end
  end

  defp decode_hex(hex, bytes) when is_binary(hex) and byte_size(hex) == bytes * 2 do
    case Base.decode16(hex, case: :lower) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :malformed}
    end
  end

  defp decode_hex(_other, _bytes), do: {:error, :malformed}

  # --- NIP-01 string escaping ---
  # Exactly: \" \\ \n \r \t \b \f; other C0 controls as lowercase \u00xx
  # (what JSON.stringify does, hence what reference clients hash);
  # everything else, including all non-ASCII, verbatim UTF-8.
  defp json_string(nil), do: ~s("")

  defp json_string(string) when is_binary(string),
    do: "\"" <> escape(string, "") <> "\""

  defp escape(<<>>, acc), do: acc
  defp escape(<<?", rest::binary>>, acc), do: escape(rest, acc <> "\\\"")
  defp escape(<<?\\, rest::binary>>, acc), do: escape(rest, acc <> "\\\\")
  defp escape(<<?\n, rest::binary>>, acc), do: escape(rest, acc <> "\\n")
  defp escape(<<?\r, rest::binary>>, acc), do: escape(rest, acc <> "\\r")
  defp escape(<<?\t, rest::binary>>, acc), do: escape(rest, acc <> "\\t")
  defp escape(<<?\b, rest::binary>>, acc), do: escape(rest, acc <> "\\b")
  defp escape(<<?\f, rest::binary>>, acc), do: escape(rest, acc <> "\\f")

  defp escape(<<c, rest::binary>>, acc) when c < 0x20,
    do: escape(rest, acc <> "\\u00" <> String.pad_leading(Integer.to_string(c, 16), 2, "0") |> String.downcase())

  defp escape(<<c::utf8, rest::binary>>, acc), do: escape(rest, acc <> <<c::utf8>>)
end
```

Note on the `c < 0x20` clause: build the `\u00xx` piece first (`hex = c |> Integer.to_string(16) |> String.pad_leading(2, "0") |> String.downcase()`), then `acc <> "\\u00" <> hex` — the pipeline in the sketch above has the wrong precedence; write it as two lines. Use an iodata accumulator (`[acc | piece]` + `IO.iodata_to_binary/1`) instead of `<>` if you prefer; behavior is what the tests pin.

Confirm against the bitcoinex source: `Signature.parse_signature/1` accepts a 64-byte binary; `Point.lift_x/1` accepts a 32-byte binary; `Schnorr.verify_signature/3` argument order `(point, z, signature)`.

- [ ] **Step 3: Run, format, commit**

`mix test test/media_centaur/nostr && mix compile --warnings-as-errors && mix format && mix credo --strict lib/media_centaur/nostr`

```bash
git add lib/media_centaur/nostr/event.ex test/media_centaur/nostr/event_test.exs
git commit -m "feat(nostr): Event — NIP-01 serialization, id, BIP-340 sign/verify, wire form

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 3: `Nostr.Filter`

**Files:** `lib/media_centaur/nostr/filter.ex`, `test/media_centaur/nostr/filter_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule MediaCentaur.Nostr.FilterTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Nostr.Filter

  test "builds only the keys given, in NIP-01 wire form" do
    filter = Filter.new(authors: ["ab", "cd"], kinds: [32160], since: 1_700_000_000, limit: 50, tags: %{"d" => ["tmdb:movie:603"]})

    assert Filter.to_map(filter) == %{
             "authors" => ["ab", "cd"],
             "kinds" => [32160],
             "since" => 1_700_000_000,
             "limit" => 50,
             "#d" => ["tmdb:movie:603"]
           }
  end

  test "an empty filter is an empty map" do
    assert Filter.to_map(Filter.new([])) == %{}
  end

  test "ids and until are supported; unknown options raise" do
    assert Filter.to_map(Filter.new(ids: ["ef"], until: 5)) == %{"ids" => ["ef"], "until" => 5}
    assert_raise KeyError, fn -> Filter.new(kind: 1) end
  end
end
```

- [ ] **Step 2: `Filter`**

```elixir
defmodule MediaCentaur.Nostr.Filter do
  @moduledoc """
  A NIP-01 subscription filter — what a `REQ` asks a relay for. Built
  from keyword options; `to_map/1` yields the wire map (only the keys
  set), with tag filters as `"#<name>"` entries.
  """

  defstruct ids: nil, authors: nil, kinds: nil, since: nil, until: nil, limit: nil, tags: %{}

  @type t :: %__MODULE__{
          ids: [String.t()] | nil,
          authors: [String.t()] | nil,
          kinds: [non_neg_integer()] | nil,
          since: non_neg_integer() | nil,
          until: non_neg_integer() | nil,
          limit: pos_integer() | nil,
          tags: %{optional(String.t()) => [String.t()]}
        }

  @keys [:ids, :authors, :kinds, :since, :until, :limit, :tags]

  @doc "Builds a filter; raises `KeyError` on an unknown option."
  @spec new(keyword()) :: t()
  def new(opts) do
    Enum.reduce(opts, %__MODULE__{}, fn {key, value}, filter ->
      if key in @keys, do: Map.put(filter, key, value), else: raise(KeyError, key: key, term: opts)
    end)
  end

  @doc "The wire map for `[\"REQ\", sub_id, filter]`."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = filter) do
    base =
      [:ids, :authors, :kinds, :since, :until, :limit]
      |> Enum.reject(&is_nil(Map.get(filter, &1)))
      |> Map.new(&{Atom.to_string(&1), Map.get(filter, &1)})

    Enum.reduce(filter.tags, base, fn {name, values}, acc -> Map.put(acc, "#" <> name, values) end)
  end
end
```

- [ ] **Step 3: Run, format, credo, commit**

`mix test test/media_centaur/nostr && mix compile --warnings-as-errors && mix format && mix credo --strict lib/media_centaur/nostr`

```bash
git add lib/media_centaur/nostr/filter.ex test/media_centaur/nostr/filter_test.exs
git commit -m "feat(nostr): Filter — NIP-01 subscription filters

Claude-Session: https://claude.ai/code/session_01BtdwbisvyUNfLHWmKvSwLz"
```

---

### Task 4: Precommit + campaign

- [ ] `mix precommit` (full) — PASSED, zero new warnings; `mix deps.audit` clean with `bitcoinex`.
- [ ] `docs/architecture.md`: if it lists bounded contexts, add one line for `MediaCentaur.Nostr` (protocol library, no deps) — mirror the format of neighbours; skip if the file has no such list.
- [ ] `campaigns/friends-recommendations.md` Status: "Layer 2 (`MediaCentaur.Nostr`: `Keys`, `Event`, `Filter`; `bitcoinex` dep) landed 2026-09-02; next: layer 3 (`Friends.Identity` + Friends tab identity block)." Add to Next steps: "**Layer 4 gotchas recorded:** `Mint.WebSocket` API sketch and the fake-relay approach (`WebSock` handler under Bandit `port: 0`) are in the Nostr research notes (session 2026-09-02); `mint_web_socket` is not yet a dep."
- [ ] Commit: `docs(campaign): Nostr protocol layer landed; next = identity` with the trailer.

---

## Self-review

**Spec coverage:** `Nostr.Keys` (generate, derive, npub/nsec, hex) → Task 1. `Nostr.Event` (struct, canonical serialization, id, sign/verify, JSON) → Task 2. `Nostr.Filter` → Task 3. `Nostr.Connection` → deliberately next layer. Tests against BIP-340 vector 0 (Keys), NIP-01 escaping rules pinned (Event).

**Type consistency:** `Keys.generate/0`, `pubkey/1`, `valid_secret?/1`, `private_key!/1`, `parse_pubkey/1`, `to_npub/1`, `from_npub/1`, `to_nsec/1`, `from_nsec/1`; `Event.new/1`, `serialize/1`, `id/1`, `sign/2`, `verify/1`, `to_map/1`, `from_map/1`, `tag_value/2`; `Filter.new/1`, `to_map/1` — used with those names throughout.

**Placeholders:** none.
