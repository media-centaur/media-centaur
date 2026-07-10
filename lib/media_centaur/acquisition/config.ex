defmodule MediaCentaur.Acquisition.Config do
  @moduledoc """
  Reads Prowlarr connection settings from the application config.

  `available?/0` returns true only when Prowlarr is configured (URL +
  API key). Download-client slots live in `MediaCentaur.Downloads`
  (`configured_clients/0`) — Prowlarr drives search and grab; the
  download clients drive progress display.
  """

  @doc "Returns true when Prowlarr is configured and acquisition features are available."
  @spec available?() :: boolean()
  def available? do
    url = MediaCentaur.Config.get(:prowlarr_url)

    is_binary(url) and url != "" and
      MediaCentaur.Secret.present?(MediaCentaur.Config.get(:prowlarr_api_key))
  end

  @doc "Returns the configured Prowlarr URL, or nil."
  @spec url() :: String.t() | nil
  def url, do: MediaCentaur.Config.get(:prowlarr_url)

  @doc """
  Returns the configured Prowlarr API key wrapped as a `Secret`, or `nil`.
  Use `Secret.expose/1` at the boundary where the raw value must be sent.
  """
  @spec api_key() :: MediaCentaur.Secret.t() | nil
  def api_key, do: MediaCentaur.Config.get(:prowlarr_api_key)
end
