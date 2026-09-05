defmodule MediaCentaurWeb.DiscoveryLive.ActivityWords do
  @moduledoc """
  The words for an activity's kind, in one place: the verb the title
  modal puts after the actor ("recommended", "watched S02E05", "started
  tracking"), the noun the delete verb and its flash name
  ("recommendation", "watched activity", "tracking activity"), the
  statement that joins actor and verb, and the presence sentence a
  person card leads with ("watched S02E05 of Sample Show").
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Format

  @doc "The past-tense verb for a kind, with the episode for a watched series."
  @spec verb(Activity.kind(), Episode.t() | nil) :: String.t()
  def verb(:recommendation, _episode), do: "recommended"
  def verb(:watched, nil), do: "watched"

  def verb(:watched, %Episode{season_number: season, episode_number: episode}),
    do: "watched #{Format.episode_label(season, episode)}"

  def verb(:tracking, _episode), do: "started tracking"

  @doc "The noun a kind's delete verb names."
  @spec noun(Activity.kind()) :: String.t()
  def noun(:recommendation), do: "recommendation"
  def noun(:watched), do: "watched activity"
  def noun(:tracking), do: "tracking activity"

  @doc """
  \"<actor> <verb>\" — the actor is the friend's nickname, or \"You\"
  for an own activity.
  """
  @spec statement(String.t(), Activity.kind(), Episode.t() | nil) :: String.t()
  def statement(actor, kind, episode), do: "#{actor} #{verb(kind, episode)}"

  @doc """
  The presence sentence: the verb and the title — "recommended Sample
  Movie", "watched S02E05 of Sample Show", "started tracking Sample Show".
  """
  @spec presence(Activity.kind(), Episode.t() | nil, String.t()) :: String.t()
  def presence(:watched, %Episode{} = episode, title_name),
    do: verb(:watched, episode) <> " of " <> title_name

  def presence(kind, episode, title_name), do: verb(kind, episode) <> " " <> title_name
end
