defmodule MediaCentaur.ErrorReports.ContextSnapshotTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.ContextSnapshot

  defmodule PipelineContext do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def gather(ids), do: %{"stage" => "import", "ids" => ids}
    @impl true
    def vitals, do: %{"queue_depth" => 3}
  end

  defmodule DeadVitals do
    @behaviour MediaCentaur.ErrorReports.IncidentContext
    @impl true
    def vitals, do: raise("subsystem down")
  end

  defp entry(message, ts) do
    Entry.new(%{
      id: System.unique_integer([:positive]),
      timestamp: ts,
      level: :error,
      component: :pipeline,
      message: message
    })
  end

  setup do
    registry = %{pipeline: PipelineContext, watcher: DeadVitals}
    ts = ~U[2026-05-31 12:00:00Z]

    buffer = [
      entry("import failed for tmdb 8587 at /movies/secret.mkv", ts),
      entry("unrelated heartbeat tick", ts)
    ]

    {:ok, registry: registry, buffer: buffer}
  end

  test "assembles all five sections", %{registry: registry, buffer: buffer} do
    snapshot =
      ContextSnapshot.assemble(:pipeline, %{tmdb_id: 8587},
        buffer_entries: buffer,
        registry: registry,
        crash_reason: "** (RuntimeError) boom"
      )

    assert Enum.sort(Map.keys(snapshot)) ==
             ["contributor", "crash_reason", "lead_up", "triggering_ids", "vitals"]

    assert snapshot["contributor"] == %{"stage" => "import", "ids" => %{tmdb_id: 8587}}
    assert snapshot["crash_reason"] == "** (RuntimeError) boom"
    assert snapshot["triggering_ids"] == %{"tmdb_id" => 8587}
  end

  test "redacts lead-up messages but flags lines sharing a triggering id", %{
    registry: registry,
    buffer: buffer
  } do
    snapshot =
      ContextSnapshot.assemble(:pipeline, %{tmdb_id: 8587}, buffer_entries: buffer, registry: registry)

    [correlated_line, other_line] = snapshot["lead_up"]

    # The path is redacted out of the stored message...
    refute correlated_line["message"] =~ "/movies/secret.mkv"
    assert correlated_line["message"] =~ "<path>"
    # ...but the line is flagged because it carries the triggering tmdb id.
    assert correlated_line["correlated"] == true
    assert other_line["correlated"] == false
  end

  test "gathers vitals from every subsystem, degrading a dead one to unavailable", %{
    registry: registry,
    buffer: buffer
  } do
    snapshot = ContextSnapshot.assemble(:pipeline, %{}, buffer_entries: buffer, registry: registry)

    assert snapshot["vitals"][:pipeline] == %{"queue_depth" => 3}
    assert snapshot["vitals"][:watcher] == "unavailable"
  end
end
