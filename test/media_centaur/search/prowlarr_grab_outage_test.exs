defmodule MediaCentaur.Search.ProwlarrGrabOutageTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Search.Prowlarr

  # The one classification both the retry loop and the manual pick read:
  # is a failed grab about the infrastructure (Prowlarr, or the client
  # behind it) rather than the release?
  describe "grab_outage?/1" do
    test "Prowlarr's 5xx for a download client it cannot reach is an outage" do
      body = %{"description" => "DownloadClientUnavailableException: Unable to connect to SABnzbd"}
      assert Prowlarr.grab_outage?({:http_error, 500, body})
    end

    test "any other 5xx is about the release, not the infrastructure" do
      # Prowlarr answered, so it is reachable and nothing marks it down —
      # a retry loop that did not charge an attempt for this would ask
      # again every probe cadence forever. The attempt ladder paces it.
      refute Prowlarr.grab_outage?(
               {:http_error, 500,
                %{"description" => "NzbDrone.Core.Exceptions.ReleaseUnavailableException: gone"}}
             )

      refute Prowlarr.grab_outage?({:http_error, 502, ""})
      refute Prowlarr.grab_outage?({:http_error, 503, %{}})
    end

    test "a transport error is an outage" do
      assert Prowlarr.grab_outage?(%Req.TransportError{reason: :econnrefused})
    end

    test "a 4xx is about the release, not the infrastructure" do
      refute Prowlarr.grab_outage?({:http_error, 400, %{"message" => "guid not found"}})
      refute Prowlarr.grab_outage?({:http_error, 404, %{}})
    end

    test "a result with no indexer id is a bad release" do
      refute Prowlarr.grab_outage?(:missing_indexer_id)
    end
  end
end
