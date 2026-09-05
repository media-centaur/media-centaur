defmodule MediaCentaurWeb.Components.Discovery.Person do
  @moduledoc """
  One person on the Friends tab — a friend, or You — with their shelves:
  the current set of their activities by kind, one entry per title,
  newest first (UIDR-031). `presence` is their latest activity of any
  kind as a sentence plus how long ago; `nil` when nothing has been
  shared. `pubkey`, `short_npub` and `added_on` are `nil` on the You
  card, which has no footer.

  Built by `DiscoveryLive.People`, rendered by `PersonCard`. A view-model:
  every fact here was resolved by the host, the card decides nothing.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title

  defmodule Entry do
    @moduledoc "One title on a shelf: the activity behind it and what the card shows for it."

    defstruct [:activity_id, :ref, :title, :poster_url, :sentiment, :episode, :acted_at]

    @type t :: %__MODULE__{
            activity_id: String.t(),
            ref: {integer(), Title.media_type()},
            title: Title.t(),
            poster_url: String.t() | nil,
            sentiment: Activity.sentiment() | nil,
            episode: Episode.t() | nil,
            acted_at: DateTime.t()
          }
  end

  defstruct [
    :id,
    :name,
    :own?,
    :pubkey,
    :short_npub,
    :added_on,
    :presence,
    watched: [],
    tracking: [],
    recommended: []
  ]

  @type presence :: %{text: String.t(), ago: String.t(), at: DateTime.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          own?: boolean(),
          pubkey: String.t() | nil,
          short_npub: String.t() | nil,
          added_on: Date.t() | nil,
          presence: presence() | nil,
          watched: [Entry.t()],
          tracking: [Entry.t()],
          recommended: [Entry.t()]
        }
end
