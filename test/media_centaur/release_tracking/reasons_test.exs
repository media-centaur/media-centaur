defmodule MediaCentaur.ReleaseTracking.ReasonsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.Reasons

  # ADR-065: a tracked title exists while a tracking reason holds, or while it
  # carries an explicit disarm. The two reasons are not equivalent — the library
  # reason is a default and evaporates; the watchlist reason is an act.

  defp facts(overrides \\ %{}) do
    Map.merge(
      %{
        mode: :watch,
        media_type: :tv_series,
        library_reason?: false,
        watchlist_reason?: false,
        movie_in_library?: false
      },
      overrides
    )
  end

  describe "retain?/1 — reasons" do
    test "retains while the library reason holds" do
      assert Reasons.retain?(facts(%{library_reason?: true}))
    end

    test "retains while the watchlist reason holds" do
      assert Reasons.retain?(facts(%{watchlist_reason?: true}))
    end

    test "retains while both hold" do
      assert Reasons.retain?(facts(%{library_reason?: true, watchlist_reason?: true}))
    end

    test "drops when no reason holds" do
      refute Reasons.retain?(facts())
    end
  end

  describe "retain?/1 — the two reasons are not equivalent" do
    test "a series armed by a person survives losing the library" do
      assert Reasons.retain?(facts(%{mode: :grab, watchlist_reason?: true, library_reason?: false}))
    end

    test "a series the app tracked only because it was owned does not" do
      refute Reasons.retain?(facts(%{mode: :global, watchlist_reason?: false, library_reason?: false}))
    end
  end

  describe "retain?/1 — an explicit disarm is durable" do
    test "retains a disarmed title with no reason left" do
      assert Reasons.retain?(facts(%{mode: :none}))
    end

    test "retains a disarmed title after the library drops it" do
      assert Reasons.retain?(facts(%{mode: :none, library_reason?: false, watchlist_reason?: false}))
    end

    test "no other mode survives losing every reason" do
      for mode <- [:watch, :ask, :grab, :global] do
        refute Reasons.retain?(facts(%{mode: mode})), "#{mode} should not survive"
      end
    end
  end

  describe "retain?/1 — a movie in the library is complete" do
    test "drops even while the watchlist reason holds" do
      refute Reasons.retain?(
               facts(%{media_type: :movie, movie_in_library?: true, watchlist_reason?: true})
             )
    end

    test "drops even while disarmed — completion beats the durable disarm" do
      refute Reasons.retain?(facts(%{media_type: :movie, movie_in_library?: true, mode: :none}))
    end
  end

  describe "seed_mode/1 — auto-grab is opt-in" do
    test "a person arming a watchlist entry seeds Watch, never the global default" do
      assert Reasons.seed_mode(:watchlist) == :watch
    end

    test "the library scan seeds Global, preserving the established opt-in" do
      assert Reasons.seed_mode(:library) == :global
    end
  end
end
