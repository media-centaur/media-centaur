defmodule MediaCentaur.IntegrationHealth.VerifierTest do
  # `async: false` — reads the shared Config persistent_term at its
  # baseline, where no Prowlarr URL and no download-client slot is set.
  use MediaCentaur.Case, async: false

  alias MediaCentaur.IntegrationHealth.Verifier

  describe "run(:prowlarr)" do
    test "returns {:error, :not_configured} when no Prowlarr URL is configured" do
      # The verifier gates on `Capabilities.configured?/1` and probes through
      # `Search.Prowlarr` — it must not reach the network for an unconfigured
      # integration.
      assert {:error, :not_configured} = Verifier.run(:prowlarr)
    end
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
