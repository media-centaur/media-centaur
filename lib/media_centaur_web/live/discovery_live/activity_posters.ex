defmodule MediaCentaurWeb.DiscoveryLive.ActivityPosters do
  @moduledoc """
  Which artwork tier an activity row's poster comes from, and which
  identities still have none.

  An activity carries a TMDB identity and a title snapshot with **no
  poster path** — `Activities.Publisher` leaves artwork to the install
  reading the row, because the entity a watch came from has no TMDB
  poster path to snapshot. So the poster is the host's to resolve
  (`ReviewFlow`'s moduledoc says the same for the review modal),
  down the artwork ladder, best first:

    * the **library** entity's own poster, when this install owns the
      identity — already downloaded, and the same artwork every other
      surface paints for that title;
    * the **referenced** tier (`TmdbArtwork`), for an identity nothing
      in the library owns;
    * the TMDB **hotlink**, on the rare snapshot that carried a poster
      path.

  `missing/1` names the identities that reached the bottom of the
  ladder with nothing, for the page to warm asynchronously — without
  it a title this install does not own stays a blank cell forever,
  since no other surface warms an activity's identity.
  """

  import MediaCentaurWeb.LiveHelpers, only: [title_poster_url: 1]

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Library.Posters

  @typedoc "A TMDB identity, as the activity rows and `ExternalIds.tmdb_owners/1` key it."
  @type ref :: {integer(), :movie | :tv_series}

  @typedoc "The owning library entity per identity, from `ExternalIds.tmdb_owners/1`."
  @type owners :: %{ref() => Ecto.UUID.t()}

  @doc "The `Library.Posters` refs for every identity this install owns."
  @spec library_refs(owners()) :: [Posters.ref()]
  def library_refs(owners) do
    Enum.map(owners, fn {{_tmdb_id, media_type}, owner_id} -> {media_type, owner_id} end)
  end

  @doc """
  The poster `src` for one activity: the library tier when the owned
  entity has one, then the referenced tier, then the hotlink, then nil.
  """
  @spec url(Activity.t(), owners(), %{Posters.ref() => String.t()}) :: String.t() | nil
  def url(%Activity{} = activity, owners, library_posters) do
    library_url(activity, owners, library_posters) || title_poster_url(activity.title)
  end

  defp library_url(%Activity{} = activity, owners, library_posters) do
    case Map.get(owners, {activity.tmdb_id, activity.media_type}) do
      nil -> nil
      owner_id -> Map.get(library_posters, {activity.media_type, owner_id})
    end
  end

  @doc "The identities whose rows painted nothing, once each — what to warm."
  @spec missing([map()]) :: [ref()]
  def missing(rows) do
    for %{poster_url: nil, activity: %Activity{} = activity} <- rows,
        uniq: true,
        do: {activity.tmdb_id, activity.media_type}
  end
end
