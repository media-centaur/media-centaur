defmodule MediaCentaurWeb.Components.Discovery.Person do
  @moduledoc """
  One person on the Feed's rail and the Friends page — a friend, or You
  — as their latest acts (UIDR-046): one `Act` per title acted on,
  newest first, each flying every act on that title in mast order and
  carrying every activity behind it. Each act's `ago` is its relative
  time, anchored by the host's clock so the card takes none; the newest
  act is the person's, and a person with no acts is a tile and a name.
  `pubkey`, `short_npub` and `added_on` are nil on the You card, which
  has no foot. Nothing here says what a person withholds.

  Built by `DiscoveryLive.People`, rendered by `PersonCard`. A view-model:
  every fact here was resolved by the host, the card decides nothing.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Flag

  defmodule Entry do
    @moduledoc "One activity behind an act: what the opened card's row and the title modal need."

    defstruct [:activity_id, :kind, :flag, :episode, :acted_at]

    @type t :: %__MODULE__{
            activity_id: String.t(),
            kind: Activity.kind(),
            flag: Flag.flag(),
            episode: Episode.t() | nil,
            acted_at: DateTime.t()
          }
  end

  defmodule Act do
    @moduledoc """
    One title the person acted on: what the strip shows for it — the
    poster under its flags, in mast order, `gold` naming the flags at
    the grade — and every activity behind it, newest first. The newest
    activity's id, time, ago and episode are the act's: the press opens
    it, the ago is its.
    """

    defstruct [
      :ref,
      :title,
      :poster_url,
      :activity_id,
      :acted_at,
      :ago,
      :episode,
      flags: [],
      gold: [],
      entries: []
    ]

    @type t :: %__MODULE__{
            ref: {integer(), Title.media_type()},
            title: Title.t(),
            poster_url: String.t() | nil,
            activity_id: String.t(),
            acted_at: DateTime.t(),
            ago: String.t(),
            episode: Episode.t() | nil,
            flags: [Flag.flag()],
            gold: [Flag.flag()],
            entries: [Entry.t()]
          }
  end

  defstruct [:id, :name, :own?, :pubkey, :short_npub, :added_on, acts: []]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          own?: boolean(),
          pubkey: String.t() | nil,
          short_npub: String.t() | nil,
          added_on: Date.t() | nil,
          acts: [Act.t()]
        }
end
