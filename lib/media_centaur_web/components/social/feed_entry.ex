defmodule MediaCentaurWeb.Components.Social.FeedEntry do
  @moduledoc """
  One row on the Feed or on the person page (UIDR-038, UIDR-045,
  UIDR-054): what the row shows, every fact resolved by the host. On the
  Feed a row is one author's action on one title (`SocialLive.FeedEntries`);
  on the person page it is one person's acts on one title, folded
  (`SocialLive.People`).

  `author` is the person as the reader sees them (`Social.Person`), and
  nil on the person page, where the page is one person: the row then
  draws no identity tile and no name. `subject` decides the verb's
  person and whether Ignore renders (never for `:you`). `kind` and
  `episode` are the newest act's: the verb (`ActivityWords.verb_phrase/3`)
  and, on a series, the episode's name in the words slot. `glyphs` are
  the flags drawn after the verb, each at its grade (`Title.Grade`): the
  review's sentiment alone on the Feed, every act on the title on the
  person page. `text` is the review's words, or nil. `poster_url` is the
  row's one picture, resolved by the host down `TitleArtwork`'s ladder;
  nil shows the empty slot. `slots` is the toolbar (`ToolbarSlots`).
  `ago` is the relative time, anchored by the host's `now`.
  Where this could be confused with a library entry, say *feed row*.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Social.Person
  alias MediaCentaur.TMDB.Title
  alias MediaCentaurWeb.Components.Social.ToolbarSlots
  alias MediaCentaurWeb.Components.Title.Flag
  alias MediaCentaurWeb.Components.Title.Grade

  defstruct [
    :id,
    :activity_id,
    :ref,
    :title,
    :poster_url,
    :author,
    :subject,
    :kind,
    :episode,
    :text,
    :acted_at,
    :ago,
    :slots,
    glyphs: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          activity_id: String.t(),
          ref: {integer(), Title.media_type()},
          title: Title.t(),
          poster_url: String.t() | nil,
          author: Person.t() | nil,
          subject: :friend | :you,
          kind: Activity.kind(),
          episode: Episode.t() | nil,
          glyphs: [{Flag.flag(), Grade.t()}],
          text: String.t() | nil,
          acted_at: DateTime.t(),
          ago: String.t(),
          slots: ToolbarSlots.t()
        }
end
