defmodule MediaCentaur.ErrorReports.DiagnosticEvent do
  @moduledoc """
  A single durable `warning`/`error` log event — the append-only feed behind
  `:log` incidents.

  One row per captured event. `message` is already redacted and normalized
  (`Redactor.normalize/1`) at capture time, and `metadata` holds only
  scalar-pruned logger metadata (triggering ids kept; titles/paths redacted),
  so a row is safe to persist as-is. `fingerprint` is the stable
  `{component, normalized_message}` hash that groups an event into its
  incident; `occurred_at` is the log event's own timestamp (distinct from the
  row's `inserted_at`), and the retention prune walks by it.

  `component` is stored as a string rather than an enum: the taxonomy is open
  (uncategorizable events fall back to a generic component) and we never want
  capture to reject an unknown component.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  @levels [:warning, :error]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          fingerprint: String.t(),
          component: String.t(),
          level: :warning | :error,
          message: String.t(),
          module: String.t() | nil,
          metadata: map(),
          occurred_at: DateTime.t()
        }

  schema "diagnostic_events" do
    field :fingerprint, :string
    field :component, :string
    field :level, Ecto.Enum, values: @levels
    field :message, :string
    field :module, :string
    field :metadata, :map, default: %{}
    field :occurred_at, :utc_datetime_usec

    timestamps()
  end

  @doc "Captured levels persisted as diagnostic events."
  @spec levels() :: [atom()]
  def levels, do: @levels

  @doc """
  Builds the insert changeset for a captured event.

  `:message` and `:metadata` are expected to be already redacted by the caller.
  """
  @spec changeset(map()) :: Ecto.Changeset.t()
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:fingerprint, :component, :level, :message, :module, :metadata, :occurred_at])
    |> validate_required([:fingerprint, :component, :level, :message, :occurred_at])
  end
end
