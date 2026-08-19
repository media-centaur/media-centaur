defmodule MediaCentaur.Downloads.ClientConfig do
  @moduledoc """
  One configured download-client slot, as a value.

  Config storage stays flat keys — the pre-existing `download_client_*`
  keys are the **torrent slot** and `usenet_download_client_*` is the
  **usenet slot** — but everything above `MediaCentaur.Settings.Config` consumes
  slots in this shape, via `MediaCentaur.Downloads.configured_clients/0`.
  One slot per protocol: Prowlarr routes each grab by the indexer's
  protocol, so MC never needs N clients of the same protocol.

  Credentials differ per client family: qBittorrent authenticates with
  `username`/`password`, SABnzbd with `api_key`. Secrets stay wrapped
  as `MediaCentaur.Secret` — drivers `expose/1` at the HTTP boundary.
  """

  alias MediaCentaur.Secret

  @enforce_keys [:protocol, :type, :url]
  defstruct [:protocol, :type, :url, :username, :password, :api_key]

  @type protocol :: :torrent | :usenet

  @type t :: %__MODULE__{
          protocol: protocol(),
          type: String.t(),
          url: String.t(),
          username: String.t() | nil,
          password: Secret.t() | nil,
          api_key: Secret.t() | nil
        }

  @doc """
  Which protocol slot a client type string belongs to. Used to route
  Prowlarr-detected clients to the right Settings form. Nil for types
  MC has no driver for.
  """
  @spec protocol_for_type(String.t() | nil) :: protocol() | nil
  def protocol_for_type("qbittorrent"), do: :torrent
  def protocol_for_type("sabnzbd"), do: :usenet
  def protocol_for_type(_), do: nil
end
