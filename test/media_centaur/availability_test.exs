defmodule MediaCentaur.AvailabilityTest do
  # Sync: `report/3` writes `:persistent_term`, which the sandbox restores at check-in.
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Availability
  alias MediaCentaur.Availability.Status
  alias MediaCentaur.Topics

  @t0 ~U[2026-09-17 20:00:00Z]
  @t1 ~U[2026-09-17 20:01:00Z]

  describe "status/1 and up?/1" do
    test "a dependency nobody has observed is up" do
      assert %Status{dependency: :prowlarr, state: :up} = Availability.status(:prowlarr)
      assert Availability.up?(:prowlarr)
      assert Availability.up?({:handoff, :usenet})
    end
  end

  describe "report/3" do
    test "the first down observation is a change, broadcast on the availability topic" do
      Topics.subscribe(Topics.availability_updates())

      assert {:changed, {:down, @t0, :unreachable}} =
               Availability.report(:prowlarr, {:down, :unreachable}, now: @t0)

      assert_receive {:availability_changed, :prowlarr, {:down, @t0, :unreachable}}
      refute Availability.up?(:prowlarr)
      assert Availability.up?({:handoff, :usenet})
    end

    test "a repeated down observation is unchanged and not broadcast, but is recorded" do
      Topics.subscribe(Topics.availability_updates())
      {:changed, _state} = Availability.report(:prowlarr, {:down, :unreachable}, now: @t0)
      assert_receive {:availability_changed, :prowlarr, _state}

      assert :unchanged = Availability.report(:prowlarr, {:down, :blind}, now: @t1, retry_at: @t1)

      refute_receive {:availability_changed, :prowlarr, _state}, 50

      assert %Status{state: {:down, @t0, :blind}, observed_at: @t1, retry_at: @t1} =
               Availability.status(:prowlarr)
    end

    test "recovery is a change back to up" do
      Topics.subscribe(Topics.availability_updates())

      {:changed, _state} =
        Availability.report({:handoff, :torrent}, {:down, :client_unavailable}, now: @t0)

      assert_receive {:availability_changed, {:handoff, :torrent}, _state}

      assert {:changed, :up} = Availability.report({:handoff, :torrent}, :up, now: @t1)
      assert_receive {:availability_changed, {:handoff, :torrent}, :up}
      assert Availability.up?({:handoff, :torrent})
    end

    test "an up observation on an up dependency is unchanged and writes nothing" do
      assert :unchanged = Availability.report(:prowlarr, :up, now: @t1)
      assert :persistent_term.get({Availability, :prowlarr}, nil) == nil
    end
  end

  describe "available?/1" do
    test "is false while down even when the integration is configured" do
      {:changed, _state} = Availability.report(:prowlarr, {:down, :rejected}, now: @t0)

      refute Availability.available?(:prowlarr)
    end

    test "is false for an unconfigured integration even when up" do
      # The test environment configures no Prowlarr and no download client.
      assert Availability.up?(:prowlarr)
      refute Availability.available?(:prowlarr)
      refute Availability.available?({:handoff, :usenet})
    end
  end
end
