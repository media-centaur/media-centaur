defmodule MediaCentaur.ErrorReports.FaultLifecycleTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ErrorReports.Incident
  alias MediaCentaur.ErrorReports.Store

  defp at(offset_seconds), do: DateTime.add(DateTime.utc_now(), offset_seconds, :second)

  describe "raise_fault/1" do
    test "opens a :subsystem incident grouped by {component, kind}" do
      assert {:ok, %Incident{} = incident} =
               Store.raise_fault(%{
                 component: :watcher,
                 kind: :drive_offline,
                 severity: :error,
                 occurred_at: at(0),
                 message: "drive /mnt/media is offline"
               })

      assert incident.origin == :subsystem
      assert incident.component == "watcher"
      assert incident.kind == "drive_offline"
      assert incident.severity == :error
      assert incident.status == :open
      assert incident.fingerprint == "subsystem:watcher:drive_offline"
      assert incident.count == 1
    end

    test "the headline becomes the incident's title and message" do
      assert {:ok, %Incident{} = incident} =
               Store.raise_fault(%{
                 component: :social,
                 kind: :relays_unreachable,
                 severity: :error,
                 occurred_at: at(0),
                 message: "No relay reachable",
                 display_title: "No relay reachable"
               })

      assert incident.display_title == "No relay reachable"
      assert incident.message == "No relay reachable"
    end

    test "re-raising while open keeps one incident, advancing last_seen and count" do
      {:ok, _} = Store.raise_fault(fault(occurred_at: at(0)))
      {:ok, incident} = Store.raise_fault(fault(occurred_at: at(30)))

      assert incident.count == 2
      assert DateTime.after?(incident.last_seen, at(0))
      assert [_only_one] = Store.list_incidents()
    end

    test "raising after a resolve opens a fresh incident" do
      {:ok, first} = Store.raise_fault(fault(occurred_at: at(0)))
      {:ok, _resolved} = Store.resolve_fault(:watcher, :drive_offline, at(10))
      {:ok, second} = Store.raise_fault(fault(occurred_at: at(20)))

      assert second.id != first.id
      assert second.status == :open
      assert length(Store.list_incidents()) == 2
    end
  end

  describe "resolve_fault/3" do
    test "resolves the open incident for the fault, stamping resolved_at" do
      {:ok, _} = Store.raise_fault(fault(occurred_at: at(0)))

      assert {:ok, %Incident{status: :resolved, resolved_at: resolved_at}} =
               Store.resolve_fault(:watcher, :drive_offline, at(10))

      assert resolved_at
      assert Store.get_open_subsystem_incident(:watcher, :drive_offline) == nil
    end

    test "is a no-op when nothing is open for that fault" do
      assert Store.resolve_fault(:watcher, :drive_offline, at(0)) == {:ok, :none}
    end
  end

  defp fault(overrides) do
    Map.merge(
      %{component: :watcher, kind: :drive_offline, severity: :error, message: "offline"},
      Map.new(overrides)
    )
  end
end
