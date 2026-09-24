defmodule MediaCentaurWeb.DiscoveryLive.ActivityWords do
  @moduledoc """
  The words for an activity's kind, in one place: the verb
  ("reviewed", "watched S02E05", "wants to watch" — "want to watch"
  when You are the subject), the noun the delete verb and its flash
  name ("review", "watched activity", "listing"), and the presence
  sentence a person card leads with ("watched S02E05 of Sample Show",
  "wants to watch Sample Show").
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Format

  @typedoc "Who the sentence is about: a friend, third person, or You, second person."
  @type subject :: :friend | :you

  @doc """
  The verb for a kind, agreeing with its subject: "wants to watch" for
  a friend, "want to watch" for You; "reviewed" and "watched" do not
  change. The episode rides on a watched series. A listing is present
  tense: the wish stands.
  """
  @spec verb(Activity.kind(), Episode.t() | nil, subject()) :: String.t()
  def verb(kind, episode, subject \\ :friend)
  def verb(:review, _episode, _subject), do: "reviewed"
  def verb(:watched, nil, _subject), do: "watched"

  def verb(:watched, %Episode{season_number: season, episode_number: episode}, _subject),
    do: "watched #{Format.episode_label(season, episode)}"

  def verb(:listing, _episode, :friend), do: "wants to watch"
  def verb(:listing, _episode, :you), do: "want to watch"

  @doc "The noun a kind's delete verb names."
  @spec noun(Activity.kind()) :: String.t()
  def noun(:review), do: "review"
  def noun(:watched), do: "watched activity"
  def noun(:listing), do: "listing"

  @doc """
  The presence sentence: the verb and the title — "reviewed Sample
  Movie", "watched S02E05 of Sample Show", "wants to watch Sample Show".
  """
  @spec presence(Activity.kind(), Episode.t() | nil, String.t()) :: String.t()
  def presence(:watched, %Episode{} = episode, title_name),
    do: verb(:watched, episode) <> " of " <> title_name

  def presence(kind, episode, title_name), do: verb(kind, episode) <> " " <> title_name
end
