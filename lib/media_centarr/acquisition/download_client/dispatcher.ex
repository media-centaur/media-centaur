defmodule MediaCentarr.Acquisition.DownloadClient.Dispatcher do
  @moduledoc """
  Resolves the configured `:download_client_type` string to its driver
  module. Add one clause to `driver/0` per new driver.
  """

  alias MediaCentarr.Acquisition.DownloadClient.QBittorrent
  alias MediaCentarr.Config

  @type error :: :not_configured | {:unknown_driver, String.t()}

  @spec driver() :: {:ok, module()} | {:error, error()}
  def driver do
    case Config.get(:download_client_type) do
      "qbittorrent" -> {:ok, QBittorrent}
      nil -> {:error, :not_configured}
      "" -> {:error, :not_configured}
      other -> {:error, {:unknown_driver, other}}
    end
  end
end
