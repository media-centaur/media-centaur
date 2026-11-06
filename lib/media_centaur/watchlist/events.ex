defmodule MediaCentaur.Watchlist.Events do
  @moduledoc """
  Typed payloads for the `watchlist:updates` topic (ADR-060): one struct
  per message, `@enforce_keys`, a single `broadcast/1`.

  Two things can happen to a title intent, so there are two messages,
  both under the one tuple `{:title_intent_changed, event}` — the topic
  says an intent changed, the struct says how:

    * `RungChanged` — its rung moved. Added, removed and re-graded were
      three names for that before the ladder replaced them; `rung: nil`
      is Off, which is the removal. The message describes the
      **transition** — `previous_rung` and `rung`, either of them `nil`
      for Off — plus a title snapshot, so every subscriber decides its
      own threshold from the two ends (the publisher asks whether List
      was crossed; nothing pre-reads a rung in order to fire a second
      event later).
    * `CaughtUp` — its caught-up point was set: the season and episode
      the person is now caught up through.
  """

  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  defmodule RungChanged do
    @moduledoc """
    A title's rung moved from `previous_rung` to `rung`; `nil` on either
    side is Off (no record). `title` is the snapshot the move was made
    with: the title the person acted on, or — on a move to Off — the
    store's snapshot of the title, a bare identity when the store never
    held it (ADR-071). Subscribers refresh whatever they derived from it.

    `actor` is the profile whose act moved it, or `nil` when no person
    did — a sweep, a seed, a repair. Only a person's act is shared with
    friends (ADR-082); everything derived from the rung follows it
    whoever moved it.
    """
    alias MediaCentaur.Profiles.Actor

    @enforce_keys [:tmdb_id, :media_type, :title, :previous_rung, :rung, :actor]
    defstruct [:tmdb_id, :media_type, :title, :previous_rung, :rung, :actor]

    @type t :: %__MODULE__{
            tmdb_id: integer(),
            media_type: :movie | :tv_series,
            title: Title.t(),
            previous_rung: TitleIntent.rung() | nil,
            rung: TitleIntent.rung() | nil,
            actor: Actor.t() | nil
          }
  end

  defmodule CaughtUp do
    @moduledoc "A title's caught-up point was set to `season` and `episode`."
    @enforce_keys [:tmdb_id, :media_type, :season, :episode]
    defstruct [:tmdb_id, :media_type, :season, :episode]

    @type t :: %__MODULE__{
            tmdb_id: integer(),
            media_type: :movie | :tv_series,
            season: pos_integer(),
            episode: pos_integer()
          }
  end

  @type t :: RungChanged.t() | CaughtUp.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%struct{} = event) when struct in [RungChanged, CaughtUp],
    do: Topics.publish(Topics.watchlist_updates(), {:title_intent_changed, event})
end
