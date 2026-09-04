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
  alias MediaCentaur.Console
  alias MediaCentaur.ErrorReports.Contributors
  alias MediaCentaur.ErrorReports.Headline
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
    :sample_entries,
    # Derived display facet (Headline.derive/1 over the normalized
    # message), not part of the bucket's identity — hence not enforced.
    headline: ""
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
          sample_entries: [sample_entry()],
          headline: binary()
        }

  @doc """
  Projects a durable `%Incident{}` (plus its recent event samples) into the
  in-memory bucket the Status page renders. Pure — no DB, no PubSub.
  """
  @spec from_incident(Incident.t(), [sample_entry()]) :: t()
  def from_incident(%Incident{} = incident, sample_entries) do
    %__MODULE__{
      fingerprint: incident.fingerprint,
      component: component_atom(incident.component),
      normalized_message: incident.message || "",
      display_title: incident.display_title || "",
      headline: headline(incident),
      severity: incident.severity,
      count: incident.count,
      first_seen: incident.first_seen,
      last_seen: incident.last_seen,
      sample_entries: sample_entries
    }
  end

  # The row title: derived from the normalized message; incidents that
  # predate message capture fall back to their stored display title.
  defp headline(%Incident{message: message}) when is_binary(message) and message != "" do
    Headline.derive(message)
  end

  defp headline(%Incident{display_title: display_title}), do: display_title || ""

  # Incidents store the component as a string; the bucket exposes the atom the
  # rest of the UI (labels, icons) already keys on. A `:log` incident carries a
  # console log component, a `:subsystem` incident the component of a
  # registered assessor — those two taxonomies are the whole key space, so the
  # string is matched against them and anything else lands under `:system`.
  # (Matching against the atom table instead depended on which modules had
  # loaded before the boot rebuild — under dev's lazy code loading a `nostr`
  # incident bucketed as `:system` until something touched `Nostr`.)
  defp component_atom(component) when is_binary(component) do
    Enum.find(known_components(), :system, &(Atom.to_string(&1) == component))
  end

  defp known_components, do: Console.known_components() ++ Map.keys(Contributors.registry())
end
