defmodule MediaCentaur.Retention.Run do
  @moduledoc """
  One row per retention policy recording its observed pruning behavior:
  when it last ran, what it removed on that run, and the lifetime total.
  Upserted in place on every run — this table never grows beyond the
  policy count.
  """
  use Ecto.Schema

  @primary_key {:policy_key, :string, autogenerate: false}

  @type t :: %__MODULE__{
          policy_key: String.t() | nil,
          last_ran_at: DateTime.t() | nil,
          pruned_last_run: non_neg_integer(),
          pruned_total: non_neg_integer()
        }

  schema "retention_runs" do
    field :last_ran_at, :utc_datetime
    field :pruned_last_run, :integer, default: 0
    field :pruned_total, :integer, default: 0
  end
end
