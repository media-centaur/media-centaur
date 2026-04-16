defmodule MediaCentarr.Acquisition.Config do
  @moduledoc """
  Reads Prowlarr and download-client connection settings from the
  application config.

  `available?/0` returns true only when Prowlarr is configured (URL +
  API key). `download_client_available?/0` returns true when a download
  client type and URL are configured. The two are independent: Prowlarr
  drives search and grab; the download client drives progress display.
  """

  @doc "Returns true when Prowlarr is configured and acquisition features are available."
  @spec available?() :: boolean()
  def available? do
    url = MediaCentarr.Config.get(:prowlarr_url)
    api_key = MediaCentarr.Config.get(:prowlarr_api_key)
    is_binary(url) and url != "" and is_binary(api_key) and api_key != ""
  end

  @doc "Returns the configured Prowlarr URL, or nil."
  @spec url() :: String.t() | nil
  def url, do: MediaCentarr.Config.get(:prowlarr_url)

  @doc "Returns the configured Prowlarr API key, or nil."
  @spec api_key() :: String.t() | nil
  def api_key, do: MediaCentarr.Config.get(:prowlarr_api_key)

  @doc "Returns true when a download client type and URL are configured."
  @spec download_client_available?() :: boolean()
  def download_client_available? do
    type = MediaCentarr.Config.get(:download_client_type)
    url = MediaCentarr.Config.get(:download_client_url)
    is_binary(type) and type != "" and is_binary(url) and url != ""
  end

  @doc "Returns the configured download client type string, or nil."
  @spec download_client_type() :: String.t() | nil
  def download_client_type, do: MediaCentarr.Config.get(:download_client_type)

  @doc "Returns the configured download client URL, or nil."
  @spec download_client_url() :: String.t() | nil
  def download_client_url, do: MediaCentarr.Config.get(:download_client_url)

  @doc "Returns the configured download client username, or nil."
  @spec download_client_username() :: String.t() | nil
  def download_client_username, do: MediaCentarr.Config.get(:download_client_username)
end
