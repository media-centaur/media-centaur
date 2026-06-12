defmodule MediaCentaur.Downloads.ConnectivityTest do
  @moduledoc """
  Spec for producer-owned connectivity grading. The grade is a fold over
  poll *outcomes* — never over snapshot age. The regression this design
  retires: consumers inferring "offline" from data age against a poll
  cadence they had to mirror (and which drifted), flagging a perfectly
  healthy client as offline whenever a snapshot was a few seconds old.
  """
  use ExUnit.Case, async: true

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
end
