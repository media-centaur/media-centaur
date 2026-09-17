defmodule MediaCentaur.IntegrationAvailabilityTest do
  # Sync: `report/3` writes `:persistent_term`, which the sandbox restores at
  # check-in. `DataCase` for the Settings row `Capabilities` reads.
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Capabilities
  alias MediaCentaur.IntegrationAvailability
  alias MediaCentaur.IntegrationAvailability.Status
  alias MediaCentaur.ProwlarrStubs
  alias MediaCentaur.Topics

  @t0 ~U[2026-09-17 20:00:00Z]
  @t1 ~U[2026-09-17 20:01:00Z]

  describe "status/1 and up?/1" do
    test "an integration nobody has observed is up, with no observation time" do
      assert %Status{integration: :prowlarr, state: :up, observed_at: nil} =
               IntegrationAvailability.status(:prowlarr)

      assert IntegrationAvailability.up?(:prowlarr)
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end
  end

  describe "handoff_slots/0" do
    test "names the two download-client protocols the hand-off is tracked per" do
      assert IntegrationAvailability.handoff_slots() == [:usenet, :torrent]
    end
  end

  describe "report/3" do
    test "the first down observation is a change, broadcast on the availability topic" do
      Topics.subscribe(Topics.integration_availability_updates())

      assert {:changed, {:down, @t0, :unreachable}} =
               IntegrationAvailability.report(:prowlarr, {:down, :unreachable}, now: @t0)

      assert_receive {:integration_availability_changed, :prowlarr, {:down, @t0, :unreachable}}
      refute IntegrationAvailability.up?(:prowlarr)
      assert IntegrationAvailability.up?({:handoff, :usenet})
    end

    test "a repeated down observation is unchanged and not broadcast, but is recorded" do
      Topics.subscribe(Topics.integration_availability_updates())

      {:changed, _state} =
        IntegrationAvailability.report(:prowlarr, {:down, :unreachable}, now: @t0)

      assert_receive {:integration_availability_changed, :prowlarr, _state}

      assert :unchanged =
               IntegrationAvailability.report(:prowlarr, {:down, :blind},
                 now: @t1,
                 retry_at: @t1
               )

      refute_receive {:integration_availability_changed, :prowlarr, _state}, 50

      assert %Status{state: {:down, @t0, :blind}, observed_at: @t1, retry_at: @t1} =
               IntegrationAvailability.status(:prowlarr)
    end

    test "recovery is a change back to up" do
      Topics.subscribe(Topics.integration_availability_updates())

      {:changed, _state} =
        IntegrationAvailability.report({:handoff, :torrent}, {:down, :client_unavailable}, now: @t0)

      assert_receive {:integration_availability_changed, {:handoff, :torrent}, _state}

      assert {:changed, :up} =
               IntegrationAvailability.report({:handoff, :torrent}, :up, now: @t1)

      assert_receive {:integration_availability_changed, {:handoff, :torrent}, :up}
      assert IntegrationAvailability.up?({:handoff, :torrent})
    end

    test "an up observation on an up integration is unchanged and writes nothing" do
      assert :unchanged = IntegrationAvailability.report(:prowlarr, :up, now: @t1)

      assert IntegrationAvailability.status(:prowlarr).observed_at == nil
    end
  end

  describe "available?/1" do
    test "is false while down even when the integration is configured" do
      {:changed, _state} =
        IntegrationAvailability.report(:prowlarr, {:down, :rejected}, now: @t0)

      refute IntegrationAvailability.available?(:prowlarr)
    end

    test "is false for an unconfigured integration even when up" do
      # The test environment configures no Prowlarr and no download client.
      assert IntegrationAvailability.up?(:prowlarr)
      refute IntegrationAvailability.available?(:prowlarr)
      refute IntegrationAvailability.available?({:handoff, :usenet})
    end

    test "a hand-off needs Prowlarr configured, not a download client of the app's own" do
      # The hand-off is Prowlarr's link to *its* download client. The
      # app's own client link is `Downloads.Connectivity`'s business and
      # says nothing about whether Prowlarr can pass a release along.
      :ok = ProwlarrStubs.mark_ready!()
      refute Capabilities.client_ready?(:usenet)

      assert IntegrationAvailability.available?({:handoff, :usenet})
    end
  end
end
