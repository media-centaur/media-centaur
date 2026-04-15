defmodule MediaCentaur.Acquisition.Config do
  @moduledoc """
  Reads Prowlarr connection settings from the application config.

  Returns `available?/0 = true` only when both `prowlarr_url` and
  `prowlarr_api_key` are present. All acquisition UI surfaces gate on this.
  """

  @doc "Returns true when Prowlarr is configured and acquisition features are available."
  @spec available?() :: boolean()
  def available? do
    url = MediaCentaur.Config.get(:prowlarr_url)
    api_key = MediaCentaur.Config.get(:prowlarr_api_key)
    is_binary(url) and url != "" and is_binary(api_key) and api_key != ""
  end

  @doc "Returns the configured Prowlarr URL, or nil."
  @spec url() :: String.t() | nil
  def url, do: MediaCentaur.Config.get(:prowlarr_url)

  @doc "Returns the configured Prowlarr API key, or nil."
  @spec api_key() :: String.t() | nil
  def api_key, do: MediaCentaur.Config.get(:prowlarr_api_key)
end
