defmodule MediaCentaur.Library.WatchProgress do
  @moduledoc """
  A row is one profile's progress on one playable item (ADR-078), unique
  on `(profile_id, playable_item_id)`; the profile is a plain id, not an
  association — `Profiles` is another context. Type information lives on
  the linked `PlayableItem`'s `(container_type, container_id)`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @behaviour MediaCentaur.Library.ProgressTracker

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID
  @timestamps_opts [type: :utc_datetime]

  schema "library_watch_progress" do
    field :position_seconds, :float, default: 0.0
    field :duration_seconds, :float, default: 0.0
    field :completed, :boolean, default: false
    field :last_watched_at, :utc_datetime
    field :profile_id, Ecto.UUID

    belongs_to :playable_item, MediaCentaur.Library.PlayableItem

    timestamps()
  end

  @type t :: %__MODULE__{}

  @impl true
  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:profile_id, :playable_item_id, :position_seconds, :duration_seconds, :completed])
    |> validate_required([:profile_id, :playable_item_id])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint([:profile_id, :playable_item_id])
  end

  # A row born of the Mark watched control: the mark alone. A hand mark is
  # not a viewing, so `last_watched_at` stays empty.
  @impl true
  def marked_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:profile_id, :playable_item_id])
    |> validate_required([:profile_id, :playable_item_id])
    |> put_change(:completed, true)
    |> unique_constraint([:profile_id, :playable_item_id])
  end

  # A position tick: the viewing in flight only. The watched mark
  # (`completed`) is not cast — starting a watched item again keeps its
  # mark. The key of a row does not move either: neither `profile_id` nor
  # `playable_item_id` is cast here.
  @impl true
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [:position_seconds, :duration_seconds])
    |> put_change(:last_watched_at, DateTime.utc_now(:second))
    |> unique_constraint([:profile_id, :playable_item_id])
  end

  @impl true
  defdelegate mark_completed_changeset(record), to: MediaCentaur.Library.ProgressTracker

  @impl true
  defdelegate mark_incomplete_changeset(record), to: MediaCentaur.Library.ProgressTracker

  @impl true
  defdelegate finish_changeset(record, duration_seconds), to: MediaCentaur.Library.ProgressTracker
end
