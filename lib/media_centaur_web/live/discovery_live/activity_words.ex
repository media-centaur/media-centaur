defmodule MediaCentaurWeb.DiscoveryLive.ActivityWords do
  @moduledoc """
  The words for an activity's kind, in one place: the verb
  ("recommended", "watched S02E05", "wants to watch"), the noun the
  delete verb and its flash name ("recommendation", "watched activity",
  "listing"), and the presence sentence a person card leads with
  ("watched S02E05 of Sample Show", "wants to watch Sample Show").
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Activities.Activity.Episode
  alias MediaCentaur.Format

  @doc "The verb for a kind, with the episode for a watched series. A listing is present tense: the wish stands."
  @spec verb(Activity.kind(), Episode.t() | nil) :: String.t()
  def verb(:recommendation, _episode), do: "recommended"
  def verb(:watched, nil), do: "watched"

  def verb(:watched, %Episode{season_number: season, episode_number: episode}),
    do: "watched #{Format.episode_label(season, episode)}"

  def verb(:listing, _episode), do: "wants to watch"

  @doc "The noun a kind's delete verb names."
  @spec noun(Activity.kind()) :: String.t()
  def noun(:recommendation), do: "recommendation"
  def noun(:watched), do: "watched activity"
  def noun(:listing), do: "listing"

  @doc """
  The presence sentence: the verb and the title — "recommended Sample
  Movie", "watched S02E05 of Sample Show", "wants to watch Sample Show".
  """
  @spec presence(Activity.kind(), Episode.t() | nil, String.t()) :: String.t()
  def presence(:watched, %Episode{} = episode, title_name),
    do: verb(:watched, episode) <> " of " <> title_name

  def presence(kind, episode, title_name), do: verb(kind, episode) <> " " <> title_name
end
