defmodule MediaCentaur.Downloads.DownloadClient.DispatcherTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Downloads.DownloadClient.{Dispatcher, QBittorrent, SABnzbd}
  alias MediaCentaur.Config

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

  defp put_config(overrides) do
    config = :persistent_term.get({Config, :config}, %{})

    blank_slots = %{
      download_client_type: nil,
      download_client_url: nil,
      usenet_download_client_type: nil,
      usenet_download_client_url: nil
    }

    :persistent_term.put(
      {Config, :config},
      config |> Map.merge(blank_slots) |> Map.merge(Map.new(overrides))
    )
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

  describe "drivers/0" do
    test "returns each configured slot paired with its driver module, torrent first" do
      put_config(
        download_client_type: "qbittorrent",
        download_client_url: "http://localhost:8080",
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert [
               {%ClientConfig{protocol: :torrent}, QBittorrent},
               {%ClientConfig{protocol: :usenet}, SABnzbd}
             ] = Dispatcher.drivers()
    end

    test "returns an empty list when nothing is configured" do
      put_config([])
      assert Dispatcher.drivers() == []
    end

    test "skips a slot whose type has no driver in this build" do
      put_config(
        download_client_type: "transmission",
        download_client_url: "http://localhost:9091",
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert [{%ClientConfig{protocol: :usenet}, SABnzbd}] = Dispatcher.drivers()
    end
  end

  describe "driver_for/1" do
    test "resolves each protocol slot to its driver module" do
      put_config(
        download_client_type: "qbittorrent",
        download_client_url: "http://localhost:8080",
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert {:ok, QBittorrent} = Dispatcher.driver_for(:torrent)
      assert {:ok, SABnzbd} = Dispatcher.driver_for(:usenet)
    end

    test "returns :not_configured when the slot is empty" do
      put_config(
        download_client_type: "qbittorrent",
        download_client_url: "http://localhost:8080"
      )

      assert {:error, :not_configured} = Dispatcher.driver_for(:usenet)
    end

    test "returns :unknown_driver when the slot's type has no driver" do
      put_config(
        usenet_download_client_type: "nzbget",
        usenet_download_client_url: "http://localhost:6789"
      )

      assert {:error, {:unknown_driver, "nzbget"}} = Dispatcher.driver_for(:usenet)
    end
  end
end
