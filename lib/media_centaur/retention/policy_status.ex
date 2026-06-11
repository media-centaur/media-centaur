defmodule MediaCentaur.Retention.PolicyStatus do
  @moduledoc """
  Read model for the Status page: a `MediaCentaur.Retention.Policy`
  merged with its recorded run stats. `last_ran_at` is `nil` until the
  policy has run (or, for `:external`/`:forever` policies that never
  report, permanently).
  """

  @enforce_keys [:key, :subsystem, :label, :description, :mode]
  defstruct [
    :key,
    :subsystem,
    :label,
    :description,
    :mode,
    :last_ran_at,
    pruned_last_run: 0,
    pruned_total: 0
  ]

  @type t :: %__MODULE__{
          key: atom(),
          subsystem: atom(),
          label: String.t(),
          description: String.t(),
          mode: MediaCentaur.Retention.Policy.mode(),
          last_ran_at: DateTime.t() | nil,
          pruned_last_run: non_neg_integer(),
          pruned_total: non_neg_integer()
        }
end
