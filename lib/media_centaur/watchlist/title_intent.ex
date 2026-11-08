defmodule MediaCentaur.Watchlist.TitleIntent do
  @moduledoc """
  One person's standing intent about one title: its TMDB identity, its
  provenance, the **rung** that says what the app should do about the
  title's releases, and the two facts only the person can state about
  it — the **caught-up point** and the **label**.

  The record holds what the person authored and nothing else: the rung,
  the note a friend's listing came with, the point and the label.
  Everything downstream — the tracked title, its calendar, its wants,
  the plans the cadence drafts — is derived from where the rung sits:

  | rung | what the app does |
  |---|---|
  | *(no record)* | nothing; the title is not on your list |
  | `:ignored` | keeps it off the Feed, and nothing else |
  | `:list` | keeps it on your list, and nothing else |
  | `:follow` | keeps its calendar, so its next release shows on the watchlist |
  | `:grab` | plans each release when it drops; the person's planning mode says whether the plan commits by itself or waits for approval |

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

  **There is no per-title grab policy.** Grab says the app plans the
  release; whether that plan commits alone or parks for review is
  `Settings.Preferences.PlanningMode`, the same answer the Download
  button gives (spec 2026-09-14). The `:ask` and `:default` rungs that
  used to carry a policy were folded into Grab and Follow by the
  `TrackingIsTwoSwitches` data migration.

  **The caught-up point** (`caught_up_season`, `caught_up_episode`) is
  the person's declared position in a series: the latest aired episode
  they have seen, wherever they saw it. A release at or before it is
  *had* — nothing needs doing about it — the same way a release the
  library holds is had (`ReleaseTracking.Had`). Follow sets it to the
  latest aired episode (Follow means caught up as of now; campaign
  `discovery.md`, decision 6 of 2026-11-04), the *Caught up* press sets
  it again, and the detail's tracking card moves it to any aired
  episode (`caught_up_changeset/2`). A movie carries none.

  **The label** (`title_name`, `title_year`) is the title's name and year
  as they were shown when the person acted on it, written on every rung
  write (`create_changeset/3`, `rung_changeset/3`). It is the record's
  own description, like its note: the store's snapshot is painted while
  the store holds one, the label when it does not (ADR-071, amended
  2026-11-04) — an Ignored record references nothing in the store, so
  after the retention sweep the label is all it has.

  Identity is `(tmdb_id, media_type)`: indexed columns taken from the
  `MediaCentaur.TMDB.Title` the person acted on (`create_changeset/3`).
  The record copies nothing else from it but the label. The title's
  render snapshot is the TMDB store's (ADR-071), attached to the virtual
  `title` by `Watchlist.Titles.attach/1` on every read, so a listed title
  is painted from the same record every other surface reads. The library
  is never referenced from here either — presence is derived at read
  time via `Library.ExternalIds` (one source of truth, cannot go stale).

  `source` is the provenance seam every future candidate source extends
  (`:import`, …); directed reviews later add nullable
  sender/recipient columns — no dead columns until then. A `:friend`
  record names the friend's review or listing it came from in
  `activity_id` — a bare uuid, because Watchlist and Activities are
  independent contexts; the web layer resolves the activity's author as
  a `Social.Person` — and, for a review, carries its text as the record's
  `note`: what the friend said when the person acted, a snapshot. A
  `:manual` record carries none, and the pairing is validated both ways.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias MediaCentaur.TMDB.Title

  @rungs [:ignored, :list, :follow, :grab]

  @typedoc "Where a person's intent about a title sits. Off is no record at all."
  @type rung :: :ignored | :list | :follow | :grab

  @typedoc "The caught-up point: a season and episode, both at least 1."
  @type caught_up :: {pos_integer(), pos_integer()}

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          tmdb_id: integer(),
          media_type: Title.media_type(),
          # The store's snapshot, attached on read; nil on a record
          # straight from a changeset.
          title: Title.t() | nil,
          rung: rung(),
          source: :manual | :friend,
          note: String.t() | nil,
          activity_id: Ecto.UUID.t() | nil,
          caught_up_season: pos_integer() | nil,
          caught_up_episode: pos_integer() | nil,
          title_name: String.t() | nil,
          title_year: String.t() | nil
        }

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "title_intents" do
    field :tmdb_id, :integer
    field :media_type, Ecto.Enum, values: [:movie, :tv_series]
    field :title, :any, virtual: true
    field :rung, Ecto.Enum, values: @rungs, default: :list
    field :source, Ecto.Enum, values: [:manual, :friend], default: :manual
    field :note, :string
    field :activity_id, Ecto.UUID
    field :caught_up_season, :integer
    field :caught_up_episode, :integer
    field :title_name, :string
    field :title_year, :string

    timestamps()
  end

  @doc """
  A new record for `title` at `rung` — the title lends its identity and
  its label and nothing else; `attrs` may carry `:source`, `:note` and
  `:activity_id`.
  """
  @spec create_changeset(Title.t(), rung(), map()) :: Ecto.Changeset.t()
  def create_changeset(%Title{} = title, rung, attrs \\ %{}) do
    %__MODULE__{}
    |> cast(attrs, [:source, :note, :activity_id])
    |> put_change(:rung, rung)
    |> put_change(:tmdb_id, title.tmdb_id)
    |> put_change(:media_type, title.media_type)
    |> put_label(title)
    |> validate_required([:tmdb_id, :media_type, :rung])
    |> validate_provenance()
    |> unique_constraint([:tmdb_id, :media_type])
  end

  @doc """
  Moves an existing record to `rung`, and writes the label from the
  `title` the move was made with — every rung write refreshes it.
  """
  @spec rung_changeset(t(), rung(), Title.t()) :: Ecto.Changeset.t()
  def rung_changeset(%__MODULE__{} = intent, rung, %Title{} = title) do
    intent
    |> change()
    |> put_change(:rung, rung)
    |> put_label(title)
    |> validate_required([:rung])
  end

  @doc """
  Sets the caught-up point. A series only — a movie has no position to
  be at — and both numbers at least 1: season 0 is specials, and the
  point names an episode the person has seen. `nil` clears it: the
  person has seen nothing yet, and every aired episode counts as out.
  """
  @spec caught_up_changeset(t(), caught_up() | nil) :: Ecto.Changeset.t()
  def caught_up_changeset(%__MODULE__{} = intent, {season, episode}) do
    intent
    |> change(caught_up_season: season, caught_up_episode: episode)
    |> validate_number(:caught_up_season, greater_than_or_equal_to: 1)
    |> validate_number(:caught_up_episode, greater_than_or_equal_to: 1)
    |> validate_series()
  end

  def caught_up_changeset(%__MODULE__{} = intent, nil) do
    intent
    |> change(caught_up_season: nil, caught_up_episode: nil)
    |> validate_series()
  end

  @doc "The record's caught-up point as a pair, or nil when none is set."
  @spec caught_up(t()) :: caught_up() | nil
  def caught_up(%__MODULE__{caught_up_season: season, caught_up_episode: episode})
      when is_integer(season) and is_integer(episode), do: {season, episode}

  def caught_up(%__MODULE__{}), do: nil

  @doc """
  The record's label as a bare `Title`: identity, name and year — what a
  surface paints when the store holds no snapshot of the title.
  """
  @spec label(t()) :: Title.t()
  def label(%__MODULE__{} = intent) do
    %Title{
      tmdb_id: intent.tmdb_id,
      media_type: intent.media_type,
      name: intent.title_name,
      year: intent.title_year
    }
  end

  # A title the person acted on from a bare identity (a friend's entry
  # before first contact) has no name to write; the label keeps what it
  # had rather than blanking it.
  defp put_label(changeset, %Title{name: nil}), do: changeset

  defp put_label(changeset, %Title{} = title),
    do: change(changeset, title_name: title.name, title_year: title.year)

  defp validate_series(changeset) do
    case get_field(changeset, :media_type) do
      :tv_series -> changeset
      _movie -> add_error(changeset, :caught_up_season, "only a series has a caught-up point")
    end
  end

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
  Whether the app plans the title's releases when they drop. Only Grab
  does; the rungs below keep a list or a calendar and nothing more. The
  one question acquisition asks about a title.
  """
  @spec grabs?(rung() | nil) :: boolean()
  def grabs?(:grab), do: true
  def grabs?(_rung), do: false

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
