defmodule MediaCentaur.Availability.StatusTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Availability.Status

  @t0 ~U[2026-09-17 20:00:00Z]
  @t1 ~U[2026-09-17 20:01:00Z]
  @t2 ~U[2026-09-17 20:02:00Z]

  describe "initial/2" do
    test "a never-observed dependency is up" do
      status = Status.initial(:prowlarr, @t0)

      assert %Status{dependency: :prowlarr, state: :up, observed_at: @t0, retry_at: nil} = status
      assert Status.up?(status)
    end
  end

  describe "fold/4" do
    test "up to up is unchanged and only moves observed_at" do
      status = Status.initial(:prowlarr, @t0)

      assert {:unchanged, %Status{state: :up, observed_at: @t1}} =
               Status.fold(status, :up, @t1, [])
    end

    test "up to down is a change dated now, carrying the reason" do
      status = Status.initial(:prowlarr, @t0)

      assert {:changed, %Status{state: {:down, @t1, :unreachable}, observed_at: @t1}} =
               Status.fold(status, {:down, :unreachable}, @t1, [])
    end

    test "down to down keeps the original onset, updates reason, observed_at and retry_at" do
      {:changed, down} =
        Status.fold(Status.initial(:prowlarr, @t0), {:down, :unreachable}, @t1, [])

      assert {:unchanged, folded} = Status.fold(down, {:down, :blind}, @t2, retry_at: @t2)
      assert folded.state == {:down, @t1, :blind}
      assert folded.observed_at == @t2
      assert folded.retry_at == @t2
      refute Status.up?(folded)
    end

    test "down to up is a change that clears retry_at" do
      {:changed, down} =
        Status.fold(Status.initial(:prowlarr, @t0), {:down, :blind}, @t1, retry_at: @t2)

      assert {:changed, %Status{state: :up, observed_at: @t2, retry_at: nil}} =
               Status.fold(down, :up, @t2, [])
    end
  end
end
