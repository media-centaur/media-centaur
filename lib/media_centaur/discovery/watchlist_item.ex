defmodule MediaCentaur.Discovery.WatchlistItem do
  @moduledoc """
  Title-level "I want to watch this" intent — an embedded
  `MediaCentaur.TMDB.Title` plus provenance.

  Identity is `(tmdb_id, media_type)`, kept as indexed columns and
  derived from the embedded title on write so there is one write path
  (`create_changeset/2`) and one read path (`item.title`). The library is
  never referenced from here — presence is derived at read time via
  `Library.ExternalIds` (one source of truth, cannot go stale).

  `source` is the provenance seam every future candidate source extends
  (`:friend`, `:import`, …); directed recommendations later add nullable
  sender/recipient columns — no dead columns until then.

  The flat `name` column is transitional: NOT NULL until the
  drop-flat-columns migration lands in a later release, so it is still
  written from the embed. Nothing reads it.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          name: String.t(),
          title: Title.t(),
          source: :manual,
          note: String.t() | nil
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "watchlist_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :name, :string
    embeds_one :title, Title
    field :source, Ecto.Enum, values: [:manual], default: :manual
    field :note, :string

    timestamps()
  end

  @doc "A new row for `title`; `attrs` may carry `:source` and `:note`."
  @spec create_changeset(Title.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%Title{} = title, attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:source, :note])
    |> put_embed(:title, title)
    |> put_change(:tmdb_id, title.tmdb_id)
    |> put_change(:media_type, title.media_type)
    |> put_change(:name, title.name)
    |> validate_required([:tmdb_id, :media_type, :name])
    |> unique_constraint([:tmdb_id, :media_type])
  end
end
