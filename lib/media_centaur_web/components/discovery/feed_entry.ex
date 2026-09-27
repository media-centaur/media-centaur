defmodule MediaCentaurWeb.Components.Discovery.FeedEntry do
  @moduledoc """
  One row on the Feed (UIDR-038, UIDR-045): one author's action on one
  title — a review or a listing — with everything the row shows and
  the two toolbar slots already resolved. `author` is the person as the
  reader sees them (`Social.Person`); its `own?` decides the verb's
  subject and whether Ignore renders (never on an own row), and
  `Format.person_name/1` gives its words. A review's `sentiment` is its
  verdict or nil, and `text` its words or nil; both nil on a listing.
  `poster_url` and `backdrop_url` are the row artwork, resolved by the
  host down `TitleArtwork`'s ladder; nil paints the inset tone.
  `offset_crop?` marks the second of two adjacent rows of one title, so
  two stills of one frame never repeat exactly (UIDR-046's crop rule).
  A view-model: every fact here was resolved by the host
  (`DiscoveryLive.FeedEntries`), the row decides nothing.

  `list_slot` is what the List position holds: the verb `:list`, the
  filled `:listed`, or the state `:following` (Follow and above; the
  row renders it as "Tracking", the UI word for a kept calendar). `download_slot` is the verb `:download` or
  `{:state, word}` — "In library", or the acquisition marker while a
  plan runs. `ago` is the relative time, anchored by the host's `now`.
  Where this could be confused with a library entry, say *feed row*.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title

  defstruct [
    :id,
    :activity_id,
    :ref,
    :title,
    :poster_url,
    :author,
    :kind,
    :sentiment,
    :text,
    :acted_at,
    :ago,
    :rung,
    :library_owner_id,
    :acquisition_state,
    :list_slot,
    :download_slot
  ]

  @type list_slot :: :list | :listed | :following
  @type download_slot :: :download | {:state, String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          activity_id: String.t(),
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          author: Person.t(),
          kind: :review | :listing,
          sentiment: Activity.sentiment() | nil,
          text: String.t() | nil,
          acted_at: DateTime.t(),
          ago: String.t(),
          rung: TitleIntent.rung() | nil,
          library_owner_id: Ecto.UUID.t() | nil,
          acquisition_state: atom() | nil,
          list_slot: list_slot(),
          download_slot: download_slot()
        }
end
