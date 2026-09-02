defmodule MediaCentaur.Social.Relay do
  @moduledoc """
  One configured relay: a `ws://` or `wss://` URL, normalized (trimmed,
  lowercase scheme and host, no userinfo, path defaults to `/`).
  Connection state is runtime (`Social.Connections.status/0`), never
  stored.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "relays" do
    field :url, :string

    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc "Changeset for a new relay row; normalizes the URL, then validates the normalized form."
  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:url])
    |> update_change(:url, &normalize/1)
    |> validate_required([:url])
    |> validate_change(:url, fn :url, url ->
      if valid?(url), do: [], else: [url: "must start with wss:// or ws://"]
    end)
    |> unique_constraint(:url)
  end

  @doc """
  Trims and canonicalizes a relay URL — lowercase scheme and host, path
  defaulting to `/` — so the same relay typed two ways is one row.
  Returns the input trimmed when it does not parse as a relay URL.

  `URI.parse/1` already downcases the scheme; the host it leaves as
  typed, so we downcase it here.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(url) when is_binary(url) do
    trimmed = String.trim(url)

    case URI.parse(trimmed) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        URI.to_string(%{uri | host: String.downcase(host), path: uri.path || "/"})

      _other ->
        trimmed
    end
  end

  defp valid?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, userinfo: nil}
      when scheme in ["ws", "wss"] and is_binary(host) and host != "" ->
        true

      _other ->
        false
    end
  end
end
