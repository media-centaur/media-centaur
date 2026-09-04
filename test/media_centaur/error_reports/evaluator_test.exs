defmodule MediaCentaur.ErrorReports.EvaluatorTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports.Evaluator
  alias MediaCentaur.ErrorReports.Store

  defmodule Healthy do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def assess, do: :ok
  end

  defmodule Stalled do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def assess, do: {:fault, :stalled, :error, %{queue: 99}}
  end

  defmodule Headlined do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def assess, do: {:fault, :queue_stalled, :error, %{headline: "Import queue has stalled"}}
  end

  defmodule Crasher do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def assess, do: raise("probe blew up")
  end

  describe "plan/2" do
    test ":ok resolves every open kind and raises nothing" do
      assert Evaluator.plan(:ok, ["stalled", "lagging"]) == %{
               raises: [],
               resolves: ["stalled", "lagging"]
             }
    end

    test "a fault raises its kind and resolves the others" do
      assert Evaluator.plan({:fault, :stalled, :error, %{}}, ["stalled", "lagging"]) ==
               %{raises: [{:stalled, :error}], resolves: ["lagging"]}
    end

    test "a fault with no open kinds raises only" do
      assert Evaluator.plan({:fault, :degraded, :warning, %{}}, []) ==
               %{raises: [{:degraded, :warning}], resolves: []}
    end
  end

  describe "run/1" do
    test "raises a fault when an assessor reports one" do
      Evaluator.run(%{pipeline: Stalled})

      assert %{severity: :error, status: :open} =
               Store.get_open_subsystem_incident(:pipeline, :stalled)
    end

    test "resolves a previously-raised fault once the assessor recovers" do
      Evaluator.run(%{pipeline: Stalled})
      assert Store.get_open_subsystem_incident(:pipeline, :stalled)

      Evaluator.run(%{pipeline: Healthy})
      assert Store.get_open_subsystem_incident(:pipeline, :stalled) == nil
    end

    test "the fault's headline titles the incident; a fault without one is named after its kind" do
      Evaluator.run(%{pipeline: Headlined, tmdb: Stalled})

      assert %{display_title: "Import queue has stalled", message: "Import queue has stalled"} =
               Store.get_open_subsystem_incident(:pipeline, :queue_stalled)

      assert %{display_title: "Stalled"} = Store.get_open_subsystem_incident(:tmdb, :stalled)
    end

    test "a healthy assessor with nothing open does nothing" do
      Evaluator.run(%{tmdb: Healthy})

      assert Store.open_subsystem_kinds(:tmdb) == []
    end

    test "a crashing assessor is skipped without raising or resolving" do
      # Pre-existing open fault for the component must survive a crashing probe.
      {:ok, _} =
        Store.raise_fault(%{
          component: :broken,
          kind: :prior,
          severity: :warning,
          occurred_at: DateTime.utc_now()
        })

      Evaluator.run(%{broken: Crasher})

      assert Store.get_open_subsystem_incident(:broken, :prior)
    end
  end
end
