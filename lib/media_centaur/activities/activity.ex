defmodule MediaCentaur.Activities.Activity do
  @moduledoc """
  One activity: a signed addressable event — a recommendation (kind
  32160), a title watched (32161) or a release tracked (32162) —
  translated into a row.

  Identity is `(author_pubkey, kind, tmdb_id, media_type)` — the event's
  kind and address — so a newer event of the same kind for the same title
  from the same author replaces the row — embed included, hence
  `on_replace: :delete`: the snapshot in the newer event is the whole
  truth, never a field-wise merge onto the older one. `raw_event` keeps
  the signed wire form for republishing to a relay that lacks it. Sent vs
  received is derived by comparing `author_pubkey` with the identity; no
  stored direction column can disagree with the signature.

  Per-kind payload: `sentiment` (`:like` or `:love`, the strength the
  recommendation pennant shows) and `note` on a recommendation; `episode`
  on a watched TV series (the episode finished, `Episode`), nil for a
  movie. A tracking activity carries only the title. `sentiment` is
  `:like` on every other kind's row — the column default, never read.

  Two times per record (see `Translation`): `acted_at` and `deleted_at`
  are **domain** times — when the person acted — and are what the app
  orders and shows by. The **wire** times that decide which copy wins
  live in the stored events, `event_created_at/1` and
  `deletion_created_at/1`; nothing else reads `created_at`.

  A withdrawn activity is a **tombstone**, not a deleted row:
  `deleted_at` is the deletion event's time and `deletion_event` its
  signed wire form. The row stays hidden while relays keep sending the
  old event, and the deletion can be republished to a relay that lacks
  it. A newer event for the same kind and address revives the row
  (`changeset/2` clears both fields: an activity event is by definition
  live).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @kinds [:recommendation, :watched, :tracking]
  @sentiments [:like, :love]

  defmodule Episode do
    @moduledoc "The episode a watched activity names on a TV series: season and episode numbers, and the episode's name when known."
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            season_number: pos_integer(),
            episode_number: pos_integer(),
            name: String.t() | nil
          }

    @primary_key false
    embedded_schema do
      field :season_number, :integer
      field :episode_number, :integer
      field :name, :string
    end

    @doc "Casts an episode; both numbers are required and positive."
    @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
    def changeset(episode \\ %__MODULE__{}, attrs) do
      episode
      |> cast(attrs, [:season_number, :episode_number, :name])
      |> validate_required([:season_number, :episode_number])
      |> validate_number(:season_number, greater_than_or_equal_to: 0)
      |> validate_number(:episode_number, greater_than: 0)
    end
  end

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "activities" do
    field :kind, Ecto.Enum, values: @kinds
    field :event_id, :string
    field :author_pubkey, :string
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    embeds_one :title, Title, on_replace: :delete
    field :sentiment, Ecto.Enum, values: @sentiments, default: :like
    field :note, :string
    embeds_one :episode, Episode, on_replace: :delete
    field :acted_at, :utc_datetime
    field :raw_event, :map
    field :deleted_at, :utc_datetime
    field :deletion_event, :map

    timestamps()
  end

  @type kind :: :recommendation | :watched | :tracking
  @type sentiment :: :like | :love

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          kind: kind(),
          event_id: String.t(),
          author_pubkey: String.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          title: Title.t(),
          sentiment: sentiment(),
          note: String.t() | nil,
          episode: Episode.t() | nil,
          acted_at: DateTime.t(),
          raw_event: map(),
          deleted_at: DateTime.t() | nil,
          deletion_event: map() | nil
        }

  @doc "Every activity kind."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Every recommendation sentiment, weakest first."
  @spec sentiments() :: [sentiment()]
  def sentiments, do: @sentiments

  @fields [
    :kind,
    :event_id,
    :author_pubkey,
    :tmdb_id,
    :media_type,
    :sentiment,
    :note,
    :acted_at,
    :raw_event
  ]

  @doc "A row from `Translation.from_event/1` attrs; the embeds are replaced wholesale."
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(activity \\ %__MODULE__{}, attrs) do
    activity
    |> cast(Map.drop(attrs, [:title, :episode]), @fields)
    |> put_embed(:title, attrs.title)
    |> put_embed(:episode, Map.get(attrs, :episode))
    |> validate_required(@fields -- [:note])
    |> put_change(:deleted_at, nil)
    |> put_change(:deletion_event, nil)
    |> unique_constraint(:event_id)
    |> unique_constraint([:author_pubkey, :kind, :tmdb_id, :media_type])
  end

  @doc "Marks the row withdrawn by a deletion event: its time and its signed wire form."
  @spec tombstone_changeset(%__MODULE__{}, %{deleted_at: DateTime.t(), deletion_event: map()}) ::
          Ecto.Changeset.t()
  def tombstone_changeset(%__MODULE__{} = activity, attrs) do
    activity
    |> cast(attrs, [:deleted_at, :deletion_event])
    |> validate_required([:deleted_at, :deletion_event])
  end

  @doc "Whether the row is a tombstone."
  @spec deleted?(%__MODULE__{}) :: boolean()
  def deleted?(%__MODULE__{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  @doc "The wire time (`created_at`, Unix seconds) of the row's activity event."
  @spec event_created_at(%__MODULE__{}) :: non_neg_integer()
  def event_created_at(%__MODULE__{raw_event: %{"created_at" => at}}), do: at

  @doc "The wire time of the deletion that withdrew the row, or nil for a live row."
  @spec deletion_created_at(%__MODULE__{}) :: non_neg_integer() | nil
  def deletion_created_at(%__MODULE__{deletion_event: %{"created_at" => at}}), do: at
  def deletion_created_at(%__MODULE__{deletion_event: nil}), do: nil
end
