defmodule MediaCentaur.Social.Identity do
  @moduledoc """
  This install's Nostr identity: one secp256k1 keypair. The secret lives
  in the sensitive `nostr_secret_key` config key (hex, `MediaCentaur.Secret`
  wrapped at rest and in memory); the public key is derived on read.

  Generated on first use (`ensure/0`) — called by the Settings Social section when
  opened, and by `Activities.recommend/2` when a user recommends a
  title before ever opening the tab. Replaced only by `import_nsec/1`.
  Both broadcast `Social.Events.IdentityChanged` so relay connections
  re-sign.
  """

  alias MediaCentaur.Social.Events
  alias MediaCentaur.Social.Events.IdentityChanged
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

  @doc "The x-only public key (lowercase hex) or nil."
  @spec pubkey() :: String.t() | nil
  def pubkey do
    case secret() do
      %Secret{} = wrapped -> Keys.pubkey(wrapped)
      nil -> nil
    end
  end

  @doc "The NIP-19 `npub` form of the public key, or nil."
  @spec npub() :: String.t() | nil
  def npub do
    case pubkey() do
      nil -> nil
      hex -> Keys.to_npub(hex)
    end
  end

  @doc "The NIP-19 `nsec` form of the secret, or nil. Reveal only on request."
  @spec export_nsec() :: String.t() | nil
  def export_nsec do
    case secret() do
      %Secret{} = wrapped -> Keys.to_nsec(wrapped)
      nil -> nil
    end
  end

  @doc "Replaces the identity with the pasted nsec (whitespace tolerated)."
  @spec import_nsec(String.t()) :: :ok | {:error, :invalid_secret}
  def import_nsec(nsec) when is_binary(nsec) do
    case Keys.from_nsec(String.trim(nsec)) do
      {:ok, %Secret{} = wrapped} ->
        store!(wrapped)
        :ok

      {:error, _reason} ->
        {:error, :invalid_secret}
    end
  end

  defp generate!, do: store!(Keys.generate())

  defp store!(%Secret{} = wrapped) do
    :ok = Config.update(@key, Secret.expose(wrapped))
    Events.broadcast(%IdentityChanged{pubkey: Keys.pubkey(wrapped)})
    secret()
  end
end
