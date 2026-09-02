defmodule MediaCentaur.Recommendations.Recommendation do
  @moduledoc """
  One recommendation: a signed kind-32160 event translated into a row.

  Identity is `(author_pubkey, tmdb_id, media_type)` — the event's
  address — so a newer event for the same title from the same author
  replaces the row (`recommended_at` decides) — embed included, hence
  `on_replace: :delete`: the snapshot in the newer event is the whole
  truth, never a field-wise merge onto the older one. `raw_event` keeps the
  signed wire form for republishing to a relay that lacks it. Sent vs
  received is derived by comparing `author_pubkey` with the identity;
  no stored direction column can disagree with the signature.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "recommendations" do
    field :event_id, :string
    field :author_pubkey, :string
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    embeds_one :title, Title, on_replace: :delete
    field :note, :string
    field :recommended_at, :utc_datetime
    field :raw_event, :map

    timestamps()
  end

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          event_id: String.t(),
          author_pubkey: String.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          title: Title.t(),
          note: String.t() | nil,
          recommended_at: DateTime.t(),
          raw_event: map()
        }

  @fields [:event_id, :author_pubkey, :tmdb_id, :media_type, :note, :recommended_at, :raw_event]

  @doc "A row from `Translation.from_event/1` attrs; the embed is replaced wholesale."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(rec \\ %__MODULE__{}, attrs) do
    rec
    |> cast(Map.delete(attrs, :title), @fields)
    |> put_embed(:title, attrs.title)
    |> validate_required(@fields -- [:note])
    |> unique_constraint(:event_id)
    |> unique_constraint([:author_pubkey, :tmdb_id, :media_type])
  end
end
