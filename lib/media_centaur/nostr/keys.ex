defmodule MediaCentaur.Nostr.Keys do
  @moduledoc """
  secp256k1 keypairs as Nostr uses them: a 32-byte secret, its x-only
  32-byte public key (BIP-340), and the NIP-19 bech32 forms `nsec` /
  `npub`. In-app representation is lowercase hex; the secret rides in
  `MediaCentaur.Secret` and is exposed in exactly three places:
  `private_key!/1` (used by both `pubkey/1` and the signing call in
  `Event`), `to_nsec/1`, and `Identity.store!/1` (persisting a new or
  imported secret to config).

  `bitcoinex` accepts a zero scalar as a private key; we do not
  (`valid_secret?/1` enforces `1 <= d < n`).
  """

  alias Bitcoinex.Bech32
  alias Bitcoinex.Secp256k1.Point
  alias Bitcoinex.Secp256k1.PrivateKey
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
      _other -> raise ArgumentError, "invalid Nostr secret key"
    end
  end

  @doc "Parse an x-only public key from `npub…` or 64-hex into lowercase hex."
  @spec parse_pubkey(term()) :: {:ok, hex32()} | {:error, :invalid_pubkey}
  def parse_pubkey("npub1" <> _rest = npub), do: from_npub(npub)

  def parse_pubkey(hex) when is_binary(hex) do
    with {:ok, x} <- parse_hex32(hex),
         true <- lift_x_ok?(x) do
      {:ok, String.downcase(hex)}
    else
      _other -> {:error, :invalid_pubkey}
    end
  end

  def parse_pubkey(_other), do: {:error, :invalid_pubkey}

  @doc "The NIP-19 `npub` form of an x-only public key."
  @spec to_npub(hex32()) :: String.t()
  def to_npub(pubkey_hex), do: bech32_encode!("npub", Base.decode16!(pubkey_hex, case: :mixed))

  @doc "Parses a NIP-19 `npub` back into lowercase hex."
  @spec from_npub(term()) :: {:ok, hex32()} | {:error, :invalid_pubkey}
  def from_npub(npub) do
    case bech32_decode(npub, "npub") do
      {:ok, <<_::binary-32>> = bytes} -> parse_pubkey(Base.encode16(bytes, case: :lower))
      _other -> {:error, :invalid_pubkey}
    end
  end

  @doc "The NIP-19 `nsec` form of a wrapped secret."
  @spec to_nsec(Secret.t()) :: String.t()
  def to_nsec(%Secret{} = secret),
    do: bech32_encode!("nsec", Base.decode16!(Secret.expose(secret), case: :mixed))

  @doc "Parses a NIP-19 `nsec` back into a wrapped secret."
  @spec from_nsec(term()) :: {:ok, Secret.t()} | {:error, :invalid_secret}
  def from_nsec(nsec) do
    with {:ok, <<_::binary-32>> = bytes} <- bech32_decode(nsec, "nsec"),
         hex = Base.encode16(bytes, case: :lower),
         true <- valid_secret?(hex) do
      {:ok, Secret.wrap(hex)}
    else
      _other -> {:error, :invalid_secret}
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

  defp lift_x_ok?(x), do: match?({:ok, _point}, Point.lift_x(x))

  defp bech32_encode!(hrp, <<_::binary-32>> = bytes) do
    {:ok, five} = Bech32.convert_bits(:binary.bin_to_list(bytes), 8, 5, true)
    {:ok, encoded} = Bech32.encode(hrp, five, :bech32)
    encoded
  end

  # bech32 is case-insensitive but `Bech32.decode/1` returns the hrp as
  # written, so normalize before matching the prefix.
  defp bech32_decode(encoded, expected_hrp) when is_binary(encoded) do
    with {:ok, {:bech32, ^expected_hrp, five}} <- Bech32.decode(String.downcase(encoded)),
         {:ok, bytes} <- Bech32.convert_bits(five, 5, 8, false) do
      {:ok, :binary.list_to_bin(bytes)}
    else
      _other -> :error
    end
  end

  defp bech32_decode(_other, _hrp), do: :error
end
