defmodule MediaCentaur.ErrorReports.RetentionPolicies do
  @moduledoc """
  Retention policies owned by ErrorReports: the diagnostic-event log is
  bounded by a time window, and resolved incidents age out once they've
  had a generous revisit window. Open/acknowledged incidents are never
  pruned — they represent unresolved state, not history.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Retention.Policy

  @event_retention_days 30
  @resolved_incident_retention_days 90

  @impl true
  def policies do
    [
      %Policy{
        key: :diagnostic_events,
        subsystem: :system,
        label: "Diagnostic events",
        description: "Diagnostic log events older than #{@event_retention_days} days are deleted.",
        mode: :sweep,
        run: fn -> Store.prune_events(days_ago(@event_retention_days)) end
      },
      %Policy{
        key: :resolved_incidents,
        subsystem: :system,
        label: "Resolved incidents",
        description:
          "Incidents resolved more than #{@resolved_incident_retention_days} days ago are " <>
            "deleted. Open and acknowledged incidents are kept indefinitely.",
        mode: :sweep,
        run: fn -> Store.prune_resolved_incidents(days_ago(@resolved_incident_retention_days)) end
      }
    ]
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
end
