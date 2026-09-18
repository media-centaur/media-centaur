defmodule MediaCentaur.IntegrationAvailability.StatusTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.IntegrationAvailability.Status

  @t0 ~U[2026-09-17 20:00:00Z]
  @t1 ~U[2026-09-17 20:01:00Z]
  @t2 ~U[2026-09-17 20:02:00Z]

  describe "initial/1" do
    test "a never-observed integration is up and carries no observation time" do
      status = Status.initial(:prowlarr)

      assert %Status{integration: :prowlarr, state: :up, observed_at: nil, retry_at: nil} = status
      assert Status.up?(status)
    end
  end

  describe "fold/4" do
    test "up to up is unchanged — the value is returned untouched" do
      status = Status.initial(:prowlarr)

      # The store writes nothing on an up observation of an up
      # integration, so the value must not claim a fresher observation
      # than the one `:persistent_term` holds.
      assert {:unchanged, ^status} = Status.fold(status, :up, @t1, [])

      observed = %{status | observed_at: @t0}
      assert {:unchanged, ^observed} = Status.fold(observed, :up, @t1, [])
    end

    test "up to down is a change dated now, carrying the reason" do
      status = Status.initial(:prowlarr)

      assert {:changed, %Status{state: {:down, @t1, :unreachable}, observed_at: @t1}} =
               Status.fold(status, {:down, :unreachable}, @t1, [])
    end

    test "down to down keeps the original onset, updates reason, observed_at and retry_at" do
      {:changed, down} =
        Status.fold(Status.initial(:prowlarr), {:down, :unreachable}, @t1, [])

      assert {:unchanged, folded} = Status.fold(down, {:down, :blind}, @t2, retry_at: @t2)
      assert folded.state == {:down, @t1, :blind}
      assert folded.observed_at == @t2
      assert folded.retry_at == @t2
      refute Status.up?(folded)
    end

    test "a rate-limited integration is down for a reason of its own" do
      status = Status.initial(:tmdb)

      assert {:changed, %Status{state: {:down, @t1, :rate_limited}}} =
               Status.fold(status, {:down, :rate_limited}, @t1, [])
    end

    test "down to up is a change that clears retry_at" do
      {:changed, down} =
        Status.fold(Status.initial(:prowlarr), {:down, :blind}, @t0, retry_at: @t2)

      assert {:changed, %Status{state: :up, observed_at: @t2, retry_at: nil}} =
               Status.fold(down, :up, @t2, [])
    end
  end
end
