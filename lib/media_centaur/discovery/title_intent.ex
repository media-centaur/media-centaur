defmodule MediaCentaur.Discovery.TitleIntent do
  @moduledoc """
  One person's standing intent about one title: an embedded
  `MediaCentaur.TMDB.Title`, its provenance, and the **rung** that says
  what the app should do about the title's releases.

  The rung is the whole ladder, and it is the only authored thing in
  release tracking. Everything downstream — the tracked title, its
  calendar, its wants, the plans the cadence drafts — is derived from
  where this sits:

  | rung | what the app does |
  |---|---|
  | *(no record)* | nothing; the title is not on your list |
  | `:ignored` | keeps it off the Feed, and nothing else |
  | `:list` | keeps it on your list, and nothing else |
  | `:follow` | keeps its calendar, so releases appear under Coming up |
  | `:ask` | parks a draft plan when a release drops |
  | `:grab` | downloads it |
  | `:default` | follows the global auto-grab setting, live |

  **Off is the absence of a record, never a stored value.** That is what
  makes "turning tracking off deletes it" a property of the schema
  instead of a rule something has to remember to apply, and it is why
  there is no durable-disarm state to keep: nothing but a person can put
  a title back on the ladder, so nothing can silently re-arm it.

  **Ignored is a record, below List.** Off is no opinion; Ignored is the
  person's decision that the title is not for them, and the one thing it
  does is keep friends' reviews and listings of it off the Feed.
  Wanting the title later — any rung at List or above — replaces it,
  the way every other move on the ladder does.

  Identity is `(tmdb_id, media_type)`, kept as indexed columns and
  derived from the embedded title on write so there is one write path
  (`create_changeset/3`) and one read path (`intent.title`). The library
  is never referenced from here — presence is derived at read time via
  `Library.ExternalIds` (one source of truth, cannot go stale).

  `source` is the provenance seam every future candidate source extends
  (`:import`, …); directed reviews later add nullable
  sender/recipient columns — no dead columns until then. A `:friend`
  record names the friend's review or listing it came from in
  `activity_id` — a bare uuid, because Discovery and Activities are
  independent contexts; the web layer resolves the nickname from the
  activity's author — and, for a review, carries its text as the record's
  `note`: what the friend said when the person acted, a snapshot. A
  `:manual` record carries none, and the pairing is validated both ways.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @rungs [:ignored, :list, :follow, :ask, :grab, :default]

  @typedoc "Where a person's intent about a title sits. Off is no record at all."
  @type rung :: :ignored | :list | :follow | :ask | :grab | :default

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          title: Title.t(),
          rung: rung(),
          source: :manual | :friend,
          note: String.t() | nil,
          activity_id: Ecto.UUID.t() | nil
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "title_intents" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    embeds_one :title, Title, on_replace: :delete
    field :rung, Ecto.Enum, values: @rungs, default: :list
    field :source, Ecto.Enum, values: [:manual, :friend], default: :manual
    field :note, :string
    field :activity_id, Ecto.UUID

    timestamps()
  end

  @doc "A new record for `title` at `rung`; `attrs` may carry `:source`, `:note` and `:activity_id`."
  @spec create_changeset(Title.t(), rung(), map()) :: Ecto.Changeset.t()
  def create_changeset(%Title{} = title, rung, attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:source, :note, :activity_id])
    |> put_change(:rung, rung)
    |> put_embed(:title, title)
    |> put_change(:tmdb_id, title.tmdb_id)
    |> put_change(:media_type, title.media_type)
    |> validate_required([:tmdb_id, :media_type, :rung])
    |> validate_provenance()
    |> unique_constraint([:tmdb_id, :media_type])
  end

  @doc "Moves an existing record to `rung`, refreshing the title snapshot."
  @spec rung_changeset(t(), rung(), Title.t() | nil) :: Ecto.Changeset.t()
  def rung_changeset(%__MODULE__{} = intent, rung, title \\ nil) do
    intent
    |> change()
    |> put_change(:rung, rung)
    |> maybe_refresh_title(title)
    |> validate_required([:rung])
  end

  defp maybe_refresh_title(changeset, nil), do: changeset
  defp maybe_refresh_title(changeset, %Title{} = title), do: put_embed(changeset, :title, title)

  @doc """
  The attrs a record takes when a person acts on a friend's activity —
  the one spelling of friend provenance, for every surface that lists
  or ignores a title from what a friend said (the title modal, the
  Feed's toolbar).
  """
  @spec friend_provenance(Ecto.UUID.t(), String.t() | nil) :: %{
          source: :friend,
          activity_id: Ecto.UUID.t(),
          note: String.t() | nil
        }
  def friend_provenance(activity_id, note) when is_binary(activity_id),
    do: %{source: :friend, activity_id: activity_id, note: note}

  @doc "The ladder, lowest first. Off is not on it — Off is no record."
  @spec rungs() :: [rung()]
  def rungs, do: @rungs

  @doc """
  Whether `rung` sits at or above `floor`. `nil` — no record, so Off — is
  below everything.
  """
  @spec rung_at_least?(rung() | nil, rung()) :: boolean()
  def rung_at_least?(nil, _floor), do: false

  def rung_at_least?(rung, floor) do
    Enum.find_index(@rungs, &(&1 == rung)) >= Enum.find_index(@rungs, &(&1 == floor))
  end

  @doc """
  Whether the app keeps a calendar for the title — the one question that
  decides whether a tracked title exists at all.
  """
  @spec follows_releases?(rung() | nil) :: boolean()
  def follows_releases?(rung), do: rung_at_least?(rung, :follow)

  @doc """
  Resolves a rung into the grab decision acquisition acts on: `"off"`,
  `"ask"` or `"all_releases"`.

  The single representation of that mapping. Acquisition asks whether it
  may grab; it does not model the ladder, so every rung below Ask is
  simply off from there. `:default` defers to the global setting, live,
  which is what makes flipping the global switch move every title whose
  rung has never been set to a concrete value.
  """
  @spec grab_mode(rung() | nil, String.t()) :: String.t()
  def grab_mode(:default, default), do: default
  def grab_mode(:grab, _default), do: "all_releases"
  def grab_mode(:ask, _default), do: "ask"
  def grab_mode(rung, _default) when rung in [nil, :ignored, :list, :follow], do: "off"

  # Provenance pairing: a friend-sourced item names the activity it came
  # from; a manual one carries none.
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
