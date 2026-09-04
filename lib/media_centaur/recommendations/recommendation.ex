defmodule MediaCentaur.Recommendations.Recommendation do
  @moduledoc """
  One recommendation: a signed kind-32160 event translated into a row.

  Identity is `(author_pubkey, tmdb_id, media_type)` — the event's
  address — so a newer event for the same title from the same author
  replaces the row — embed included, hence `on_replace: :delete`: the
  snapshot in the newer event is the whole truth, never a field-wise merge
  onto the older one. `raw_event` keeps the signed wire form for
  republishing to a relay that lacks it. Sent vs received is derived by
  comparing `author_pubkey` with the identity; no stored direction column
  can disagree with the signature.

  Two times per record (see `Translation`): `recommended_at` and
  `deleted_at` are **domain** times — when the person acted — and are what
  the app orders and shows by. The **wire** times that decide which copy
  wins live in the stored events, `event_created_at/1` and
  `deletion_created_at/1`; nothing else reads `created_at`.

  A withdrawn recommendation is a **tombstone**, not a deleted row:
  `deleted_at` is the deletion event's time and `deletion_event` its
  signed wire form. The row stays hidden while relays keep sending the
  old recommendation, and the deletion can be republished to a relay
  that lacks it. A newer recommendation for the same address revives the
  row (`changeset/2` clears both fields: a recommendation event is by
  definition live).
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
    field :deleted_at, :utc_datetime
    field :deletion_event, :map

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
          raw_event: map(),
          deleted_at: DateTime.t() | nil,
          deletion_event: map() | nil
        }

  @fields [:event_id, :author_pubkey, :tmdb_id, :media_type, :note, :recommended_at, :raw_event]

  @doc "A row from `Translation.from_event/1` attrs; the embed is replaced wholesale."
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(rec \\ %__MODULE__{}, attrs) do
    rec
    |> cast(Map.delete(attrs, :title), @fields)
    |> put_embed(:title, attrs.title)
    |> validate_required(@fields -- [:note])
    |> put_change(:deleted_at, nil)
    |> put_change(:deletion_event, nil)
    |> unique_constraint(:event_id)
    |> unique_constraint([:author_pubkey, :tmdb_id, :media_type])
  end

  @doc "Marks the row withdrawn by a deletion event: its time and its signed wire form."
  @spec tombstone_changeset(%__MODULE__{}, %{deleted_at: DateTime.t(), deletion_event: map()}) ::
          Ecto.Changeset.t()
  def tombstone_changeset(%__MODULE__{} = rec, attrs) do
    rec
    |> cast(attrs, [:deleted_at, :deletion_event])
    |> validate_required([:deleted_at, :deletion_event])
  end

  @doc "Whether the row is a tombstone."
  @spec deleted?(%__MODULE__{}) :: boolean()
  def deleted?(%__MODULE__{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  @doc "The wire time (`created_at`, Unix seconds) of the row's recommendation event."
  @spec event_created_at(%__MODULE__{}) :: non_neg_integer()
  def event_created_at(%__MODULE__{raw_event: %{"created_at" => at}}), do: at

  @doc "The wire time of the deletion that withdrew the row, or nil for a live row."
  @spec deletion_created_at(%__MODULE__{}) :: non_neg_integer() | nil
  def deletion_created_at(%__MODULE__{deletion_event: %{"created_at" => at}}), do: at
  def deletion_created_at(%__MODULE__{deletion_event: nil}), do: nil
end
