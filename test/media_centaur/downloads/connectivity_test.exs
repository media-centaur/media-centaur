defmodule MediaCentaur.Downloads.ConnectivityTest do
  @moduledoc """
  Spec for producer-owned connectivity grading. The grade is a fold over
  poll *outcomes* — never over snapshot age. The regression this design
  retires: consumers inferring "offline" from data age against a poll
  cadence they had to mirror (and which drifted), flagging a perfectly
  healthy client as offline whenever a snapshot was a few seconds old.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Downloads.Connectivity

  @now ~U[2026-06-12 12:00:00Z]
  @later ~U[2026-06-12 12:00:10Z]

  describe "initial/0" do
    test "starts :initializing — no poll outcome observed yet" do
      assert Connectivity.initial() == :initializing
    end
  end

  describe "poll_succeeded/1" do
    test "any successful poll grades :live, regardless of previous grade" do
      assert Connectivity.poll_succeeded(:initializing) == :live
      assert Connectivity.poll_succeeded(:live) == :live
      assert Connectivity.poll_succeeded({:transient_failure, @now}) == :live
      assert Connectivity.poll_succeeded({:offline, @now}) == :live
      assert Connectivity.poll_succeeded(:auth_failed) == :live
      assert Connectivity.poll_succeeded(:not_configured) == :live
    end
  end

  describe "poll_failed/3 — unreachable" do
    test "a single failure from healthy is a transient blip, not an outage" do
      assert Connectivity.poll_failed(:live, :unreachable, @now) ==
               {:transient_failure, @now}
    end

    test "a single failure at startup is also a transient blip" do
      assert Connectivity.poll_failed(:initializing, :unreachable, @now) ==
               {:transient_failure, @now}
    end

    test "a second consecutive failure is an outage, dated from the FIRST failure" do
      transient = Connectivity.poll_failed(:live, :unreachable, @now)
      assert Connectivity.poll_failed(transient, :unreachable, @later) == {:offline, @now}
    end

    test "continued failures keep the original outage onset" do
      offline = {:offline, @now}
      assert Connectivity.poll_failed(offline, :unreachable, @later) == {:offline, @now}
    end
  end

  describe "poll_failed/3 — auth" do
    test "credential rejection grades :auth_failed immediately (deterministic, not a blip)" do
      assert Connectivity.poll_failed(:live, :auth_failed, @now) == :auth_failed
      assert Connectivity.poll_failed({:offline, @now}, :auth_failed, @later) == :auth_failed
    end
  end

  describe "describe_failure/1 — what a failed poll says on the Status board" do
    test "a refused connection says nothing is listening" do
      assert Connectivity.describe_failure(%Req.TransportError{reason: :econnrefused}) ==
               "connection refused — nothing is listening at this address"
    end

    test "a timeout and an unknown host each name themselves" do
      assert Connectivity.describe_failure(%Req.TransportError{reason: :timeout}) == "timed out"

      assert Connectivity.describe_failure(%Req.TransportError{reason: :nxdomain}) ==
               "host name not found"
    end

    # Measured 2026-11-21: after a reboot another program took the torrent
    # client's port first, and the client's API answered 404 for 15 hours
    # under a fault that only said "Download client unreachable".
    test "a 404 says another program may hold the address" do
      assert Connectivity.describe_failure({:http_error, 404, ""}) ==
               "HTTP 404 — something else answers at this address; another program may be using the port"
    end

    test "any other HTTP status is named by its code" do
      assert Connectivity.describe_failure({:http_error, 502, "Bad Gateway"}) == "HTTP 502"
      assert Connectivity.describe_failure({:http_error, 500}) == "HTTP 500"
    end

    test "a rejected credential reads as such" do
      assert Connectivity.describe_failure(:auth_failed) == "credentials rejected"
      assert Connectivity.describe_failure({:auth_failed, "API Key Incorrect"}) == "credentials rejected"
    end

    test "a client-reported error carries the client's own words" do
      assert Connectivity.describe_failure({:api_error, "Sample failure"}) == "Sample failure"
    end
  end
end
