defmodule MediaCentaurWeb.Live.TitleDetailHost.Finish do
  @moduledoc """
  What a host does when a playback session ends (UIDR-052). A session
  that completed the final released item of a title opens that title
  with the finish prompt — in place when its detail is already open,
  otherwise by opening it. Everything else leaves the page as it was
  (play in place, UIDR-027).

  The title is identified by its **finished id**, a library id:

    * a standalone movie — its own id, which is also the session's entity;
    * a movie in a collection — the movie's own id, never the collection's.
      The collection is opened on that member, and the prompt's delete
      covers that movie's files only;
    * a series — the series id, when the session completed TMDB's latest
      aired episode (`last_episode_to_air`). Not the last episode the
      library holds: the library holds only seasons with files. Whether
      the show is finished or caught up is the open detail's `settled?`
      fact, read where the prompt renders.

  Playback cannot read TMDB, so the rule is judged here, where the
  session's completed items and the TMDB record are both readable.
  """

  @type reaction :: :ignore | {:open, String.t()} | {:in_place, String.t()}

  @doc """
  The host's reaction to a `SessionEnded` payload (map-matched, as every
  `playback:events` subscriber does), given the open detail's subject id
  (`LibraryHalf.subject_id/1`, nil when none is open), whether the
  preference is on, and the series' latest aired episode as
  `{season_number, episode_number}` (nil when the session is not a
  series or TMDB has none on record).
  """
  @spec reaction(
          %{entity_id: String.t(), completed: MapSet.t()},
          String.t() | nil,
          boolean(),
          {integer(), integer()} | nil
        ) :: reaction()
  def reaction(event, open_subject_id, enabled?, latest_aired) do
    with true <- enabled?,
         id when is_binary(id) <- finished_id(event, latest_aired) do
      if id == open_subject_id, do: {:in_place, id}, else: {:open, id}
    else
      _ -> :ignore
    end
  end

  @doc "Whether the session completed any episode — the case the host reads the TMDB record for."
  @spec episodes?(%{completed: MapSet.t()}) :: boolean()
  def episodes?(%{completed: completed}),
    do: Enum.any?(completed, &match?({:episode, _id, _season, _episode}, &1))

  @doc "TMDB's latest aired episode from a series payload, as `{season_number, episode_number}`."
  @spec latest_aired_episode(map()) :: {integer(), integer()} | nil
  def latest_aired_episode(%{
        "last_episode_to_air" => %{"season_number" => season, "episode_number" => episode}
      })
      when is_integer(season) and is_integer(episode), do: {season, episode}

  def latest_aired_episode(_payload), do: nil

  defp finished_id(%{entity_id: entity_id, completed: completed}, latest_aired) do
    Enum.find_value(completed, fn
      {:movie, id} -> id
      {:episode, _id, season, episode} when {season, episode} == latest_aired -> entity_id
      _item -> nil
    end)
  end
end
