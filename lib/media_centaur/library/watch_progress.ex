defmodule MediaCentaur.Library.WatchProgress do
  @moduledoc """
  A row is one profile's progress on one playable item (ADR-078), unique
  on `(profile_id, playable_item_id)`; the profile is a plain id, not an
  association — `Profiles` is another context. Type information lives on
  the linked `PlayableItem`'s `(container_type, container_id)`.

  A row holds two independent facts:

    * The watched mark, `completed`: this profile has seen this item. Set
      by a finish (`MediaCentaur.Library.ProgressRecords.finish/3`) or the
      Mark watched control, cleared by Mark unwatched. A position tick
      never writes it, so starting a watched item again keeps its mark.
    * The viewing in flight: an offset into the file (`position_seconds`),
      the file's duration (`duration_seconds`) and when the viewing was
      last touched (`last_watched_at`). Written by position ticks
      (`update_changeset/2`) and ended — the offset set to 0 — by a
      finish and by either watched control. It counts once the offset
      reaches 60 seconds (`ProgressRecords.viewing?/1`).

  A watched item being replayed therefore has both: the mark and a
  viewing. A hand mark is not a viewing and does not stamp
  `last_watched_at`.

  Where the profile is in a series is neither fact; it is recorded on the
  series (`MediaCentaur.Library.SeriesWatchPosition`), and the reading of
  the three together is `MediaCentaur.Library.TitleProgress`.
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
