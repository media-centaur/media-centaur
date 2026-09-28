defmodule MediaCentaurWeb.Components.Discovery.Act do
  @moduledoc """
  One title a person acted on (UIDR-046): what the person card's strip
  shows for it — the poster under its flags, in mast order, `grades`
  giving each flag's grade (`DiscoveryLive.Grade`) — and every activity behind it, newest
  first. The newest activity's id, time, ago and episode are the act's:
  the press opens it, the ago is its. Built by `DiscoveryLive.People`,
  rendered by `PersonCard`; a view-model, the card decides nothing.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.DiscoveryLive.Grade

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

  defstruct [
    :ref,
    :title,
    :poster_url,
    :activity_id,
    :acted_at,
    :ago,
    :episode,
    flags: [],
    grades: %{},
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
          grades: %{Flag.flag() => Grade.t()},
          entries: [Entry.t()]
        }
end
