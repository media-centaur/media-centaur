defmodule MediaCentaur.Search.ProwlarrGrabOutageTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Search.Prowlarr

  # The classification the retry loop and the grab's log line read: is a
  # failed grab about the infrastructure (Prowlarr unreachable, or the client
  # behind it), a release Prowlarr no longer holds, or the release itself?
  # The manual pick reads the narrower `download_client_unavailable?/1` to
  # word its flash.
  describe "grab_failure/1" do
    test "Prowlarr's 5xx for a download client it cannot reach is an outage" do
      body = %{"description" => "DownloadClientUnavailableException: Unable to connect to SABnzbd"}
      assert :outage == Prowlarr.grab_failure({:http_error, 500, body})
    end

    test "any other 5xx is about the release, not the infrastructure" do
      # Prowlarr answered, so it is reachable and nothing marks it down —
      # a retry loop that did not charge an attempt for this would ask
      # again every probe cadence forever. The attempt ladder paces it.
      assert :refused ==
               Prowlarr.grab_failure(
                 {:http_error, 500,
                  %{"description" => "NzbDrone.Core.Exceptions.ReleaseUnavailableException: gone"}}
               )

      assert :refused == Prowlarr.grab_failure({:http_error, 502, ""})
      assert :refused == Prowlarr.grab_failure({:http_error, 503, %{}})
    end

    test "a transport error is an outage" do
      assert :outage == Prowlarr.grab_failure(%Req.TransportError{reason: :econnrefused})
    end

    test "a 4xx is about the release, not the infrastructure" do
      assert :refused == Prowlarr.grab_failure({:http_error, 400, %{"message" => "guid not found"}})
      assert :refused == Prowlarr.grab_failure({:http_error, 404, %{}})
    end

    test "a result with no indexer id is a bad release" do
      assert :refused == Prowlarr.grab_failure(:missing_indexer_id)
    end

    # Measured 2026-11-21: a reboot restarted Prowlarr, which empties the
    # cache of search results a grab is looked up in. A release chosen before
    # the restart was refused with this answer and filed as two incidents.
    test "a release missing from Prowlarr's cache is classed apart from a refusal" do
      body = %{
        "description" =>
          "NzbDrone.Core.Exceptions.NzbDroneClientException: Couldn't find requested release in cache, try searching again"
      }

      assert :release_not_cached == Prowlarr.grab_failure({:http_error, 404, body})
      assert :release_not_cached == Prowlarr.grab_failure({:http_error, 500, body})
    end
  end
end
