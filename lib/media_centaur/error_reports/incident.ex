defmodule MediaCentaur.ErrorReports.Incident do
  @moduledoc """
  A durable, stateful incident record — the thing an *incident report* is
  packaged from and sent.

  An incident has one of three origins (`:log`, `:subsystem`, `:user`) and a
  lifecycle (`:open → :acknowledged → :resolved`). In Phase 1 only `:log`
  incidents exist: one per `fingerprint`, accumulating `count`/`last_seen` as
  matching events recur. The `:subsystem`/`:user` origins, the frozen context
  snapshots (`first_context`/`latest_context`), `scope`, and `user_description`
  are provisioned now but populated in later phases.

  Grouping for `:log` is by `fingerprint` (unique among non-null fingerprints);
  `:subsystem` faults group by `{component, kind}`; `:user` reports never group.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime_usec]

  @origins [:log, :subsystem, :user]
  @statuses [:open, :acknowledged, :resolved]
  @severities [:warning, :error, :critical]

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          origin: :log | :subsystem | :user,
          kind: String.t() | nil,
          component: String.t(),
          message: String.t() | nil,
          display_title: String.t() | nil,
          fingerprint: String.t() | nil,
          severity: :warning | :error | :critical,
          status: :open | :acknowledged | :resolved,
          count: non_neg_integer(),
          first_seen: DateTime.t(),
          last_seen: DateTime.t(),
          resolved_at: DateTime.t() | nil,
          first_context: map() | nil,
          latest_context: map() | nil,
          user_description: String.t() | nil,
          scope: map() | nil,
          app_version_at_first: String.t() | nil
        }

  schema "incidents" do
    field :origin, Ecto.Enum, values: @origins
    field :kind, :string
    field :component, :string
    field :message, :string
    field :display_title, :string
    field :fingerprint, :string
    field :severity, Ecto.Enum, values: @severities
    field :status, Ecto.Enum, values: @statuses, default: :open
    field :count, :integer, default: 1
    field :first_seen, :utc_datetime_usec
    field :last_seen, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :first_context, :map
    field :latest_context, :map
    field :user_description, :string
    field :scope, :map
    field :app_version_at_first, :string

    timestamps()
  end

  @doc "Valid incident origins."
  @spec origins() :: [atom()]
  def origins, do: @origins

  @doc "Valid lifecycle statuses."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "Valid severities."
  @spec severities() :: [atom()]
  def severities, do: @severities

  @doc """
  Insert changeset for a freshly-opened `:log` incident.

  Forces `origin: :log` and a non-null `fingerprint`; the unique constraint
  guards against two openers racing the same fingerprint.
  """
  @spec log_changeset(map()) :: Ecto.Changeset.t()
  def log_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :component,
      :message,
      :display_title,
      :fingerprint,
      :severity,
      :status,
      :count,
      :first_seen,
      :last_seen,
      :app_version_at_first
    ])
    |> put_change(:origin, :log)
    |> validate_required([:component, :fingerprint, :severity, :first_seen, :last_seen])
    |> unique_constraint(:fingerprint, name: :incidents_fingerprint_index)
  end

  @doc """
  Insert changeset for a freshly-raised `:subsystem` fault.

  Forces `origin: :subsystem`. Grouped by `{component, kind}` (no fingerprint).
  """
  @spec subsystem_changeset(map()) :: Ecto.Changeset.t()
  def subsystem_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :component,
      :kind,
      :message,
      :display_title,
      :severity,
      :status,
      :count,
      :first_seen,
      :last_seen
    ])
    |> put_change(:origin, :subsystem)
    |> validate_required([:component, :kind, :severity, :first_seen, :last_seen])
  end

  @doc """
  Insert changeset for a user-filed (`:user`) report. Forces `origin: :user`.
  Ungrouped — each report is its own incident with a unique `fingerprint`.
  """
  @spec user_changeset(map()) :: Ecto.Changeset.t()
  def user_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :component,
      :message,
      :display_title,
      :fingerprint,
      :severity,
      :status,
      :count,
      :first_seen,
      :last_seen,
      :user_description,
      :first_context,
      :scope,
      :app_version_at_first
    ])
    |> put_change(:origin, :user)
    |> validate_required([:fingerprint, :severity, :first_seen, :last_seen])
    |> unique_constraint(:fingerprint, name: :incidents_fingerprint_index)
  end

  @doc """
  Update changeset for a recurring `:log` incident: bumps `count` and advances
  `last_seen` (and re-opens a resolved incident if it recurs).
  """
  @spec recurrence_changeset(t(), map()) :: Ecto.Changeset.t()
  def recurrence_changeset(incident, attrs) do
    incident
    |> cast(attrs, [
      :count,
      :first_seen,
      :last_seen,
      :message,
      :display_title,
      :severity,
      :status,
      :resolved_at
    ])
    |> validate_required([:count, :last_seen])
  end
end
