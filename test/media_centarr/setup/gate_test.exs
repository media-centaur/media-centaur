defmodule MediaCentarr.Setup.GateTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.IntegrationHealth.Status
  alias MediaCentarr.Setup.Gate

  describe "check/3 — pseudo steps" do
    test ":welcome always allows advance" do
      assert :ok = Gate.check(:welcome, nil, nil)
      assert :ok = Gate.check(:welcome, %{status: :error}, nil)
    end

    test ":summary always allows advance" do
      assert :ok = Gate.check(:summary, nil, nil)
    end
  end

  describe "check/3 — non-testable steps gate on probe alone" do
    test "watch_dirs :ok passes" do
      assert :ok = Gate.check(:watch_dirs, %{status: :ok}, nil)
    end

    test "watch_dirs non-:ok blocks" do
      assert {:blocked, :probe_not_ok} = Gate.check(:watch_dirs, %{status: :error}, nil)
      assert {:blocked, :probe_not_ok} = Gate.check(:watch_dirs, %{status: :not_configured}, nil)
    end

    test "mpv :ok passes without any health record" do
      assert :ok = Gate.check(:mpv, %{status: :ok}, nil)
    end
  end

  describe "check/3 — TMDB (critical + testable)" do
    test "probe :ok + health :ok → advance allowed" do
      health = status(:tmdb, :ok)
      assert :ok = Gate.check(:tmdb, %{status: :ok}, health)
    end

    test "probe :ok + health :unknown → blocked :test_not_run" do
      health = status(:tmdb, :unknown)
      assert {:blocked, :test_not_run} = Gate.check(:tmdb, %{status: :ok}, health)
    end

    test "probe :ok + health :pending → advance allowed (re-verify in background)" do
      # `:pending` is the transient re-verify-in-progress state. The
      # background re-verify also happens at boot for already-configured
      # integrations, briefly re-gating users who'd successfully verified
      # in a prior session. Trust `configured?` + a non-`:error`
      # `test_state`: if the user has TMDB credentials and we're just
      # re-checking, let them advance. If the test eventually flips to
      # `:error`, the next render's gate sees the new state.
      health = status(:tmdb, :pending)
      assert :ok = Gate.check(:tmdb, %{status: :ok}, health)
    end

    test "probe :ok + health :error → blocked :test_failed" do
      health = status(:tmdb, :error)
      assert {:blocked, :test_failed} = Gate.check(:tmdb, %{status: :ok}, health)
    end

    test "probe :not_configured → blocked :probe_not_ok (regardless of health)" do
      health = status(:tmdb, :ok)
      assert {:blocked, :probe_not_ok} = Gate.check(:tmdb, %{status: :not_configured}, health)
    end

    test "no health record → blocked :test_not_run" do
      assert {:blocked, :test_not_run} = Gate.check(:tmdb, %{status: :ok}, nil)
    end
  end

  describe "check/3 — Prowlarr / download_client (testable but not gating)" do
    # Today only TMDB requires a successful test to advance. Prowlarr and
    # download_client are optional integrations — saved-but-untested is
    # acceptable for advancement (the user gets the test result as a UX
    # surface, but isn't blocked on it).

    test "prowlarr probe :ok passes without a health record" do
      assert :ok = Gate.check(:prowlarr, %{status: :ok}, nil)
    end

    test "prowlarr probe :ok passes even when health :error" do
      health = status(:prowlarr, :error)
      assert :ok = Gate.check(:prowlarr, %{status: :ok}, health)
    end

    test "download_client probe :ok passes without a health record" do
      assert :ok = Gate.check(:download_client, %{status: :ok}, nil)
    end
  end

  describe "blocked?/3" do
    test "true when check returns {:blocked, _}" do
      assert Gate.blocked?(:tmdb, %{status: :ok}, status(:tmdb, :unknown))
    end

    test "false when check returns :ok" do
      refute Gate.blocked?(:tmdb, %{status: :ok}, status(:tmdb, :ok))
    end
  end

  describe "reason_message/1" do
    test "every reason atom has stable text" do
      assert is_binary(Gate.reason_message(:probe_not_ok))
      assert is_binary(Gate.reason_message(:test_failed))
      assert is_binary(Gate.reason_message(:test_not_run))
    end
  end

  defp status(id, test_state) do
    %Status{id: id, configured?: true, test_state: test_state}
  end
end
