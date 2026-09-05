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
  (`:import`, …); directed recommendations later add nullable
  sender/recipient columns — no dead columns until then. A `:friend`
  item names the recommendation it came from in `activity_id` — a
  bare uuid, because Discovery and Recommendations are independent
  contexts; the web layer resolves the nickname from the
  recommendation's author. A `:manual` item carries none, and the
  pairing is validated both ways.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          title: Title.t(),
          source: :manual | :friend,
          note: String.t() | nil,
          activity_id: Ecto.UUID.t() | nil
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "watchlist_items" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    embeds_one :title, Title
    field :source, Ecto.Enum, values: [:manual, :friend], default: :manual
    field :note, :string
    field :activity_id, Ecto.UUID

    timestamps()
  end

  @doc "A new row for `title`; `attrs` may carry `:source`, `:note` and `:activity_id`."
  @spec create_changeset(Title.t(), map()) :: Ecto.Changeset.t()
  def create_changeset(%Title{} = title, attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:source, :note, :activity_id])
    |> put_embed(:title, title)
    |> put_change(:tmdb_id, title.tmdb_id)
    |> put_change(:media_type, title.media_type)
    |> validate_required([:tmdb_id, :media_type])
    |> validate_provenance()
    |> unique_constraint([:tmdb_id, :media_type])
  end

  # Provenance pairing: a friend-sourced item names its recommendation; a
  # manual one carries none.
  defp validate_provenance(changeset) do
    case {get_field(changeset, :source), get_field(changeset, :activity_id)} do
      {:friend, nil} ->
        add_error(changeset, :activity_id, "is required for a friend-sourced item")

      {:manual, id} when not is_nil(id) ->
        add_error(changeset, :activity_id, "only a friend-sourced item carries one")

      _ok ->
        changeset
    end
  end
end
