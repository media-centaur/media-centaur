defmodule MediaCentaurWeb.DiscoveryLive.ActivityArtwork do
  @moduledoc """
  An activity row's artwork — the poster and the backdrop — and which
  identities still have none.

  An activity carries a TMDB identity and a title snapshot with **no
  artwork paths** — `Activities.Publisher` leaves artwork to the install
  reading the row, because the entity a watch came from has no TMDB
  paths to snapshot. So the row's artwork is the host's to resolve
  (`ReviewFlow`'s moduledoc says the same for the review modal), down
  `MediaCentaur.TitleArtwork`'s ladder per role: the owning **library**
  entity's image — read in one batch over every owned identity, by
  `library_refs/1` and `Library.Artwork.urls_by_refs/2` per role — then
  the **referenced** tier, then the **hotlink**, dead in practice for
  both roles since the snapshot carries no paths. The band paints its
  poster at 100×150 CSS px, so the hotlink would ask `:w185`.

  `missing/1` names the identities that reached the bottom of the
  ladder with nothing in either role, for the page to warm
  asynchronously — without it a title this install does not own stays
  blank forever, since no other surface warms an activity's identity.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Library.Artwork
  alias MediaCentaur.TitleArtwork

  @typedoc "A TMDB identity, as the activity rows and `ExternalIds.tmdb_owners/1` key it."
  @type ref :: {integer(), :movie | :tv_series}

  @typedoc "The owning library entity per identity, from `ExternalIds.tmdb_owners/1`."
  @type owners :: %{ref() => Ecto.UUID.t()}

  @typedoc "The library tier's URLs per role, from `Library.Artwork.urls_by_refs/2`."
  @type library_artwork :: %{String.t() => %{Artwork.ref() => String.t()}}

  @roles ~w(poster backdrop)

  @doc "The roles a row paints — what the host reads from the library tier."
  @spec roles() :: [String.t()]
  def roles, do: @roles

  @doc "The `Library.Artwork` refs for every identity this install owns."
  @spec library_refs(owners()) :: [Artwork.ref()]
  def library_refs(owners) do
    Enum.map(owners, fn {{_tmdb_id, media_type}, owner_id} -> {media_type, owner_id} end)
  end

  @doc """
  The poster and backdrop `src` for one activity, each down the ladder:
  the library tier when the owned entity has that image, then the
  referenced tier, then the hotlink, then nil.
  """
  @spec urls(Activity.t(), owners(), library_artwork()) ::
          %{poster_url: String.t() | nil, backdrop_url: String.t() | nil}
  def urls(%Activity{} = activity, owners, library) do
    activity.title
    |> TitleArtwork.urls(library_for(activity, owners, library), :w185)
    |> Map.take([:poster_url, :backdrop_url])
  end

  defp library_for(%Activity{} = activity, owners, library) do
    case Map.get(owners, {activity.tmdb_id, activity.media_type}) do
      nil ->
        %{}

      owner_id ->
        Map.new(library, fn {role, urls} -> {role, Map.get(urls, {activity.media_type, owner_id})} end)
    end
  end

  @doc "The identities whose rows painted nothing in either role, once each — what to warm."
  @spec missing([map()]) :: [ref()]
  def missing(rows) do
    for %{activity: %Activity{} = activity} = row <- rows,
        is_nil(row.poster_url) or is_nil(row.backdrop_url),
        uniq: true,
        do: {activity.tmdb_id, activity.media_type}
  end
end
