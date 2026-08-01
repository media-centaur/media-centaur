defmodule MediaCentaur.DownloadsTest do
  # Mutates the global Config :persistent_term — same isolation pattern
  # as DispatcherTest.
  use ExUnit.Case, async: false

  alias MediaCentaur.Config
  alias MediaCentaur.Downloads
  alias MediaCentaur.Downloads.ClientConfig
  alias MediaCentaur.Secret

  setup do
    original = :persistent_term.get({Config, :config}, %{})

    on_exit(fn ->
      :persistent_term.put({Config, :config}, original)
    end)

    :ok
  end

  defp put_config(overrides) do
    config = :persistent_term.get({Config, :config}, %{})

    blank_slots = %{
      download_client_type: nil,
      download_client_url: nil,
      download_client_username: nil,
      download_client_password: nil,
      usenet_download_client_type: nil,
      usenet_download_client_url: nil,
      usenet_download_client_api_key: nil
    }

    :persistent_term.put(
      {Config, :config},
      config |> Map.merge(blank_slots) |> Map.merge(Map.new(overrides))
    )
  end

  describe "configured_clients/0" do
    test "returns an empty list when neither slot is configured" do
      put_config([])

      assert Downloads.configured_clients() == []
    end

    test "returns the torrent slot from the flat download_client_* keys" do
      put_config(
        download_client_type: "qbittorrent",
        download_client_url: "http://localhost:8080",
        download_client_username: "admin",
        download_client_password: Secret.wrap("hunter2")
      )

      assert [%ClientConfig{} = client] = Downloads.configured_clients()
      assert client.protocol == :torrent
      assert client.type == "qbittorrent"
      assert client.url == "http://localhost:8080"
      assert client.username == "admin"
      assert Secret.expose(client.password) == "hunter2"
      assert client.api_key == nil
    end

    test "returns the usenet slot from the usenet_download_client_* keys" do
      put_config(
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085",
        usenet_download_client_api_key: Secret.wrap("sab-key")
      )

      assert [%ClientConfig{} = client] = Downloads.configured_clients()
      assert client.protocol == :usenet
      assert client.type == "sabnzbd"
      assert client.url == "http://localhost:8085"
      assert Secret.expose(client.api_key) == "sab-key"
      assert client.username == nil
      assert client.password == nil
    end

    test "returns both slots, torrent first, when both are configured" do
      put_config(
        download_client_type: "qbittorrent",
        download_client_url: "http://localhost:8080",
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert [%ClientConfig{protocol: :torrent}, %ClientConfig{protocol: :usenet}] =
               Downloads.configured_clients()
    end

    test "a slot needs both type and URL to count as configured" do
      put_config(
        download_client_type: "qbittorrent",
        download_client_url: "",
        usenet_download_client_type: "",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert Downloads.configured_clients() == []
    end
  end

  describe "client_web_url/1" do
    test "returns the configured slot's URL" do
      put_config(
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert Downloads.client_web_url(:usenet) == "http://localhost:8085"
    end

    test "nil for an unconfigured slot" do
      put_config(
        usenet_download_client_type: "sabnzbd",
        usenet_download_client_url: "http://localhost:8085"
      )

      assert Downloads.client_web_url(:torrent) == nil
    end
  end
end
