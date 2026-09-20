defmodule MediaCentaur.TMDB.Store.TitleRecord do
  @moduledoc """
  One TMDB title as the app knows it: TMDB's last detail answer
  (`payload`, as received except what
  `MediaCentaur.TMDB.Store.trim_payload/1` removes — the `images` block
  beyond the selected logo, and the credits), the `etag` to revalidate
  it with, when TMDB last answered
  (`fetched_at`, moved by a 200 or a 304), when the payload last
  differed (`changed_at`), and the schedule `MediaCentaur.TMDB.Schedule`
  derives: `next_event_on`, `next_check_at` (nil when settled), and
  `settled_at` (set the first time the settled rule holds, cleared if a
  later check unsettles it).

  Written only by `MediaCentaur.TMDB.Store`. Keyed by `(media_type,
  tmdb_id)` — TMDB's movie and TV id spaces overlap.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  @type t :: %__MODULE__{}

  schema "tmdb_titles" do
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :tmdb_id, :integer
    field :payload, :map
    field :etag, :string
    field :fetched_at, :utc_datetime
    field :changed_at, :utc_datetime
    field :next_event_on, :date
    field :next_check_at, :utc_datetime
    field :settled_at, :utc_datetime

    timestamps()
  end

  @fields [
    :media_type,
    :tmdb_id,
    :payload,
    :etag,
    :fetched_at,
    :changed_at,
    :next_event_on,
    :next_check_at,
    :settled_at
  ]

  def changeset(record, attrs) do
    record
    |> cast(attrs, @fields)
    |> validate_required([:media_type, :tmdb_id, :payload, :fetched_at, :changed_at])
    |> unique_constraint([:media_type, :tmdb_id])
  end
end
