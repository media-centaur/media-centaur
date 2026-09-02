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

  alias Bitcoinex.Secp256k1.Point
  alias Bitcoinex.Secp256k1.Schnorr
  alias Bitcoinex.Secp256k1.Signature
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
  def serialize(%__MODULE__{pubkey: nil}) do
    raise ArgumentError, "cannot serialize an event without a pubkey"
  end

  def serialize(%__MODULE__{} = event) do
    tags =
      Enum.map_join(event.tags, ",", fn tag ->
        "[" <> Enum.map_join(tag, ",", &json_string/1) <> "]"
      end)

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
  def id(%__MODULE__{} = event), do: Base.encode16(:crypto.hash(:sha256, serialize(event)), case: :lower)

  @doc "Sets `pubkey` from the secret, computes `id`, signs it (BIP-340)."
  @spec sign(t(), Secret.t()) :: t()
  def sign(%__MODULE__{} = event, %Secret{} = secret) do
    aux = :binary.decode_unsigned(:crypto.strong_rand_bytes(32))
    sign_with_aux(event, secret, aux)
  end

  @doc false
  @spec sign_with_aux(t(), Secret.t(), non_neg_integer()) :: t()
  def sign_with_aux(%__MODULE__{} = event, %Secret{} = secret, aux) do
    event = %{event | pubkey: Keys.pubkey(secret)}
    id = id(event)
    z = id |> Base.decode16!(case: :lower) |> :binary.decode_unsigned()
    {:ok, signature} = Schnorr.sign(Keys.private_key!(secret), z, aux)
    %{event | id: id, sig: serialize_signature(signature)}
  end

  @doc false
  @spec serialize_signature(Signature.t()) :: String.t()
  def serialize_signature(%Signature{r: r_value, s: s_value}) do
    # bitcoinex's own serializer does not zero-pad r/s; fixed-width here.
    Base.encode16(<<r_value::big-unsigned-256, s_value::big-unsigned-256>>, case: :lower)
  end

  @doc """
  Recomputes the id and checks the signature against `pubkey`.
  `{:error, :malformed}` when a hex field is not the right shape, `pubkey` is
  64 hex chars that do not decode to a point on the curve, or `sig` is 128
  hex chars that do not parse as a valid `r, s` pair. `{:error, :bad_signature}`
  is reserved for a well-formed signature that fails Schnorr verification.
  """
  @spec verify(t()) :: :ok | {:error, :bad_id | :bad_signature | :malformed}
  def verify(%__MODULE__{} = event) do
    with {:ok, pubkey_bytes} <- decode_hex(event.pubkey, 32),
         {:ok, id_bytes} <- decode_hex(event.id, 32),
         {:ok, sig_bytes} <- decode_hex(event.sig, 64),
         :ok <- check_id(event) do
      check_signature(pubkey_bytes, id_bytes, sig_bytes)
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
      when is_binary(id) and is_binary(pubkey) and is_binary(content) and is_binary(sig) and
             is_list(tags) and is_integer(created_at) and created_at >= 0 and is_integer(kind) and
             kind >= 0 do
    if Enum.all?(tags, &tag?/1) do
      {:ok,
       %__MODULE__{
         id: id,
         pubkey: pubkey,
         created_at: created_at,
         kind: kind,
         tags: tags,
         content: content,
         sig: sig
       }}
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

  defp tag?(tag), do: is_list(tag) and Enum.all?(tag, &is_binary/1)

  defp check_id(event) do
    if id(event) == event.id, do: :ok, else: {:error, :bad_id}
  end

  defp check_signature(pubkey_bytes, id_bytes, sig_bytes) do
    with {:ok, point} <- Point.lift_x(pubkey_bytes),
         {:ok, signature} <- Signature.parse_signature(sig_bytes) do
      if Schnorr.verify_signature(point, :binary.decode_unsigned(id_bytes), signature) do
        :ok
      else
        {:error, :bad_signature}
      end
    else
      {:error, _reason} -> {:error, :malformed}
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
  # everything else verbatim. The catch-all copies one byte at a time,
  # which reproduces multi-byte UTF-8 unchanged and cannot fail on input
  # that is not valid UTF-8.
  defp json_string(string) when is_binary(string), do: IO.iodata_to_binary([?", escape(string, []), ?"])

  defp escape(<<>>, acc), do: acc
  defp escape(<<?", rest::binary>>, acc), do: escape(rest, [acc, "\\\""])
  defp escape(<<?\\, rest::binary>>, acc), do: escape(rest, [acc, "\\\\"])
  defp escape(<<?\n, rest::binary>>, acc), do: escape(rest, [acc, "\\n"])
  defp escape(<<?\r, rest::binary>>, acc), do: escape(rest, [acc, "\\r"])
  defp escape(<<?\t, rest::binary>>, acc), do: escape(rest, [acc, "\\t"])
  defp escape(<<?\b, rest::binary>>, acc), do: escape(rest, [acc, "\\b"])
  defp escape(<<?\f, rest::binary>>, acc), do: escape(rest, [acc, "\\f"])

  defp escape(<<byte, rest::binary>>, acc) when byte < 0x20 do
    hex = byte |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(2, "0")
    escape(rest, [acc, ["\\u00", hex]])
  end

  defp escape(<<byte, rest::binary>>, acc), do: escape(rest, [acc, <<byte>>])
end
