defmodule MediaCentaurWeb.Components.Discovery.FeedEntry do
  @moduledoc """
  One entry on the Feed (UIDR-038): one friend's action on one title —
  a review or a listing — with everything the card shows and the two
  toolbar slots already resolved. A review's `sentiment` is its verdict
  or nil, and `text` its words or nil; both nil on a listing. A view-model, like `Person`:
  every fact here was resolved by the host (`DiscoveryLive.FeedEntries`),
  the card decides nothing.

  `list_slot` is what the List position holds: the verb `:list`, the
  filled `:listed`, or the state `:following` (Follow and above, per
  UIDR-036's bookmark rule). `download_slot` is the verb `:download` or
  `{:state, word}` — "In library", or the acquisition marker while a
  plan runs. `ago` is the relative time, anchored by the host's `now`.
  Where this could be confused with a library entry, say *feed entry*.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.TMDB.Title

  defstruct [
    :id,
    :activity_id,
    :ref,
    :title,
    :poster_url,
    :nickname,
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
          nickname: String.t(),
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
