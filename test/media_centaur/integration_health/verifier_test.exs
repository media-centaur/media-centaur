defmodule MediaCentaur.IntegrationHealth.VerifierTest do
  # `async: false` — mutates the shared Config persistent_term to control
  # which download-client slots count as configured.
  use ExUnit.Case, async: false

  alias MediaCentaur.Config
  alias MediaCentaur.IntegrationHealth.Verifier

  setup do
    # Null the download-client config so a slot leaked from another test
    # can't make this deterministic check flaky.
    original_config = :persistent_term.get({Config, :config})

    :persistent_term.put(
      {Config, :config},
      original_config
      |> Map.put(:download_client_type, nil)
      |> Map.put(:download_client_url, nil)
      |> Map.put(:usenet_download_client_type, nil)
      |> Map.put(:usenet_download_client_url, nil)
    )

    on_exit(fn -> :persistent_term.put({Config, :config}, original_config) end)
    :ok
  end

  describe "run(:download_client)" do
    test "returns {:error, :not_configured} when no client slot is configured" do
      # Regression: the verifier used to hardcode QBittorrent.test_connection/0,
      # so a usenet-only (or unconfigured) install always probed an absent
      # torrent client and reported a spurious error. It must route through the
      # two-slot Dispatcher instead.
      assert {:error, :not_configured} = Verifier.run(:download_client)
    end
  end
end
