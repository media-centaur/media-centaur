defmodule MediaCentarr.ErrorReports.Bucket do
  @moduledoc """
  A single error fingerprint bucket held by `MediaCentarr.ErrorReports.Buckets`.

  Buckets are keyed by `fingerprint` — a stable hash of
  `{component, normalized_message}` that groups the same error across files,
  parameters, and users. `count` is the occurrence count inside the retention
  window; `sample_entries` carries up to the last 5 redacted log lines from
  the same bucket for developer context.
  """

  @enforce_keys [
    :fingerprint,
    :component,
    :normalized_message,
    :display_title,
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
          count: non_neg_integer(),
          first_seen: DateTime.t(),
          last_seen: DateTime.t(),
          sample_entries: [sample_entry()]
        }
end
