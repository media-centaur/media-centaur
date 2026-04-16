defmodule MediaCentarr.Acquisition.DownloadClient.DispatcherTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Acquisition.DownloadClient.{Dispatcher, QBittorrent}
  alias MediaCentarr.Config

  setup do
    original = :persistent_term.get({Config, :config}, %{})

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  defp set_type(type) do
    config = :persistent_term.get({Config, :config}, %{})
    :persistent_term.put({Config, :config}, Map.put(config, :download_client_type, type))
  end

  test "returns QBittorrent when type is \"qbittorrent\"" do
    set_type("qbittorrent")
    assert {:ok, QBittorrent} = Dispatcher.driver()
  end

  test "returns :not_configured when type is nil" do
    set_type(nil)
    assert {:error, :not_configured} = Dispatcher.driver()
  end

  test "returns :not_configured when type is the empty string" do
    set_type("")
    assert {:error, :not_configured} = Dispatcher.driver()
  end

  test "returns :unknown_driver for an unrecognized type" do
    set_type("transmission")
    assert {:error, {:unknown_driver, "transmission"}} = Dispatcher.driver()
  end
end
