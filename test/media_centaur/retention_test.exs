defmodule MediaCentaur.RetentionTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Retention
  alias MediaCentaur.Retention.Policy

  defmodule FixtureProvider do
    @behaviour MediaCentaur.Retention.PolicyProvider

    @impl true
    def policies do
      [
        %Policy{
          key: :fixture_sweep,
          subsystem: :system,
          label: "Fixture sweep",
          description: "Fixture rows older than 30 days are deleted.",
          mode: :sweep,
          run: fn -> 4 end
        },
        %Policy{
          key: :fixture_external,
          subsystem: :acquisition,
          label: "Fixture external",
          description: "Pruned elsewhere on its own cadence.",
          mode: :external
        },
        %Policy{
          key: :fixture_forever,
          subsystem: :playback,
          label: "Fixture forever",
          description: "Kept forever by design.",
          mode: :forever
        }
      ]
    end
  end

  defmodule RaisingProvider do
    @behaviour MediaCentaur.Retention.PolicyProvider

    @impl true
    def policies do
      [
        %Policy{
          key: :fixture_raising,
          subsystem: :system,
          label: "Fixture raising",
          description: "Always raises.",
          mode: :sweep,
          run: fn -> raise "boom" end
        },
        %Policy{
          key: :fixture_after_raise,
          subsystem: :system,
          label: "Fixture after raise",
          description: "Runs even when an earlier policy raises.",
          mode: :sweep,
          run: fn -> 2 end
        }
      ]
    end
  end

  defp with_providers(providers) do
    original = Application.fetch_env!(:media_centaur, :retention_policy_providers)
    Application.put_env(:media_centaur, :retention_policy_providers, providers)

    on_exit(fn ->
      Application.put_env(:media_centaur, :retention_policy_providers, original)
    end)
  end

  describe "record_run/2" do
    test "creates a run row on first record and accumulates on subsequent records" do
      assert :ok = Retention.record_run(:fixture_sweep, 3)

      assert %{pruned_last_run: 3, pruned_total: 3, last_ran_at: first_ran_at} =
               Retention.get_run(:fixture_sweep)

      assert :ok = Retention.record_run(:fixture_sweep, 5)

      assert %{pruned_last_run: 5, pruned_total: 8, last_ran_at: second_ran_at} =
               Retention.get_run(:fixture_sweep)

      assert DateTime.compare(second_ran_at, first_ran_at) in [:gt, :eq]
    end

    test "a zero-count run still updates last_ran_at" do
      assert :ok = Retention.record_run(:fixture_sweep, 0)

      assert %{pruned_last_run: 0, pruned_total: 0, last_ran_at: %DateTime{}} =
               Retention.get_run(:fixture_sweep)
    end

    test "a failed write is non-fatal — stats are garnish, not correctness" do
      # External pruners call record_run from boot paths (AbsenceSweeper's
      # initial TTL check). A DB error here — e.g. booting dev before the
      # migration has run — must log, not crash the calling supervisor.
      Repo.query!("ALTER TABLE retention_runs RENAME TO retention_runs_hidden")

      assert :ok = Retention.record_run(:fixture_sweep, 3)
    end
  end

  describe "policies/0" do
    test "collects policies from every configured provider" do
      with_providers([FixtureProvider])

      keys = Enum.map(Retention.policies(), & &1.key)
      assert keys == [:fixture_sweep, :fixture_external, :fixture_forever]
    end
  end

  describe "sweep/0" do
    test "runs sweep policies, records their counts, and skips other modes" do
      with_providers([FixtureProvider])

      assert :ok = Retention.sweep()

      assert %{pruned_last_run: 4, pruned_total: 4} = Retention.get_run(:fixture_sweep)
      assert Retention.get_run(:fixture_external) == nil
      assert Retention.get_run(:fixture_forever) == nil
    end

    test "a raising policy does not prevent later policies from running" do
      with_providers([RaisingProvider])

      assert {:error, _failures} = Retention.sweep()

      assert Retention.get_run(:fixture_raising) == nil
      assert %{pruned_last_run: 2} = Retention.get_run(:fixture_after_raise)
    end
  end

  describe "status_by_subsystem/0" do
    test "merges run stats into policies grouped by subsystem" do
      with_providers([FixtureProvider])
      Retention.record_run(:fixture_sweep, 7)

      status = Retention.status_by_subsystem()

      assert [%{key: :fixture_sweep, pruned_last_run: 7, pruned_total: 7, last_ran_at: %DateTime{}}] =
               status[:system]

      assert [%{key: :fixture_external, last_ran_at: nil, pruned_total: 0}] = status[:acquisition]
      assert [%{key: :fixture_forever, mode: :forever}] = status[:playback]
    end
  end
end
