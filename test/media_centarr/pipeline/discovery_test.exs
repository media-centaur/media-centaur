defmodule MediaCentarr.Pipeline.DiscoveryTest do
  @moduledoc """
  Unit tests for `MediaCentarr.Pipeline.Discovery` pure helpers.
  Pipeline integration is exercised via stage tests; this file covers
  the small classifier extracted for log-severity routing.
  """
  use ExUnit.Case, async: true

  alias MediaCentarr.Pipeline.Discovery

  describe "auth_failure?/1" do
    test "true for HTTP 401 errors" do
      assert Discovery.auth_failure?({:http_error, 401, %{"status_message" => "Invalid API key"}})
    end

    test "true for HTTP 403 errors" do
      assert Discovery.auth_failure?({:http_error, 403, %{}})
    end

    test "false for other HTTP errors" do
      refute Discovery.auth_failure?({:http_error, 500, %{}})
      refute Discovery.auth_failure?({:http_error, 404, %{}})
    end

    test "false for non-HTTP error reasons" do
      refute Discovery.auth_failure?(:timeout)
      refute Discovery.auth_failure?({:error, :nxdomain})
      refute Discovery.auth_failure?(nil)
    end
  end
end
