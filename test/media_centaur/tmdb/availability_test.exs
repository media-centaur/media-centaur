defmodule MediaCentaur.TMDB.AvailabilityTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.TMDB.Availability
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  describe "observe_request/1" do
    test "an answered request is evidence TMDB is up" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert {:changed, :up} = Availability.observe_request({:ok, :fetched})
      assert IntegrationAvailability.up?(:tmdb)
    end

    test "an answer served from the cache asked nobody, so it is no evidence" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert :unchanged = Availability.observe_request({:ok, :hit})
      refute IntegrationAvailability.up?(:tmdb)
    end

    test "a transport error, a 5xx and a 429 each open TMDB, with their own reason" do
      assert {:changed, {:down, _since, :unreachable}} =
               Availability.observe_request({:error, %Req.TransportError{reason: :timeout}})

      IntegrationAvailability.report(:tmdb, :up)

      assert {:changed, {:down, _since, :unreachable}} =
               Availability.observe_request({:error, {:http_error, 503, ""}})

      IntegrationAvailability.report(:tmdb, :up)

      assert {:changed, {:down, _since, :rate_limited}} =
               Availability.observe_request({:error, {:http_error, 429, ""}})
    end

    test "a rejected key is as useless as a dead server, and says which" do
      assert {:changed, {:down, _since, :rejected}} =
               Availability.observe_request({:error, {:http_error, 401, ""}})
    end

    test "any other 4xx is about the request, and closes nothing" do
      {:changed, _state} = IntegrationAvailability.report(:tmdb, {:down, :unreachable})

      assert :unchanged = Availability.observe_request({:error, {:http_error, 404, ""}})
      refute IntegrationAvailability.up?(:tmdb)
    end
  end
end
