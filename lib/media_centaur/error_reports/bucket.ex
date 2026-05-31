defmodule MediaCentaur.ErrorReports.Bucket do
  @moduledoc """
  A single fingerprint bucket — the cache projection of an `Incident` that
  `MediaCentaur.ErrorReports.Buckets` serves to the Status page.

  Buckets are keyed by `fingerprint` — a stable hash of
  `{component, normalized_message}` that groups the same error across files,
  parameters, and users. `count`/`first_seen`/`last_seen` mirror the durable
  incident; `severity` (`:warning | :error | :critical`) lets the UI rank and
  colour by health; `sample_entries` carries up to the last 5 redacted log
  lines for developer context.
  """
  alias MediaCentaur.ErrorReports.Incident

  @enforce_keys [
    :fingerprint,
    :component,
    :normalized_message,
    :display_title,
    :severity,
    :count,
    :first_seen,
    :last_seen,
    :sample_entries
  ]
  defstruct [
    :fingerprint,
    :component,
    :normalized_message,
    :display_title,
    :severity,
    :count,
    :first_seen,
    :last_seen,
    :sample_entries
  ]

  @type sample_entry :: %{timestamp: DateTime.t(), message: binary()}

  @type t :: %__MODULE__{
          fingerprint: binary(),
          component: atom(),
          normalized_message: binary(),
          display_title: binary(),
          severity: :warning | :error | :critical,
          count: non_neg_integer(),
          first_seen: DateTime.t(),
          last_seen: DateTime.t(),
          sample_entries: [sample_entry()]
        }

  @doc """
  Projects a durable `%Incident{}` (plus its recent event samples) into the
  in-memory bucket the Status page renders. Pure — no DB, no PubSub.
  """
  @spec from_incident(Incident.t(), [sample_entry()]) :: t()
  def from_incident(%Incident{} = incident, sample_entries) do
    %__MODULE__{
      fingerprint: incident.fingerprint,
      component: safe_component(incident.component),
      normalized_message: incident.message || "",
      display_title: incident.display_title || "",
      severity: incident.severity,
      count: incident.count,
      first_seen: incident.first_seen,
      last_seen: incident.last_seen,
      sample_entries: sample_entries
    }
  end

  # Incidents store the component as a string; the bucket exposes the atom the
  # rest of the UI (labels, icons) already keys on. The taxonomy is bounded, so
  # an unknown string falls back to `:system` rather than growing the atom table.
  defp safe_component(component) when is_binary(component) do
    String.to_existing_atom(component)
  rescue
    ArgumentError -> :system
  end
end
