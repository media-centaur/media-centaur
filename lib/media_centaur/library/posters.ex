defmodule MediaCentaur.Library.Posters do
  @moduledoc """
  Batch poster-URL resolution by entity reference, for surfaces outside the
  Library views that need artwork for a heterogeneous list of entities (e.g.
  the Status page's recently-watched feed).

  Episodes resolve to their **series'** poster — episodes carry no poster of
  their own. The result map contains entries only for refs that resolved to a
  cached poster; refs to deleted or posterless entities are simply absent, so
  callers read with `Map.get(result, ref)` and treat `nil` as "no artwork".
  """

  import Ecto.Query

  alias MediaCentaur.Library.Episode
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Repo

  @type ref :: {:movie | :episode | :video_object, Ecto.UUID.t()}

  @spec urls_by_refs([ref()]) :: %{ref() => String.t()}
  def urls_by_refs([]), do: %{}

  def urls_by_refs(refs) do
    episode_ids = for {:episode, id} <- refs, do: id
    series_by_episode = series_ids_by_episode(episode_ids)

    owners =
      Enum.flat_map(refs, fn
        {:episode, id} ->
          case series_by_episode[id] do
            nil -> []
            series_id -> [{:tv_series, series_id}]
          end

        {kind, id} ->
          [{kind, id}]
      end)

    urls = poster_urls_by_owner(owners)

    refs
    |> Enum.flat_map(fn
      {:episode, id} = ref ->
        case series_by_episode[id] && urls[{:tv_series, series_by_episode[id]}] do
          nil -> []
          url -> [{ref, url}]
        end

      {kind, id} = ref ->
        case urls[{kind, id}] do
          nil -> []
          url -> [{ref, url}]
        end
    end)
    |> Map.new()
  end

  defp series_ids_by_episode([]), do: %{}

  defp series_ids_by_episode(episode_ids) do
    from(episode in Episode,
      join: season in assoc(episode, :season),
      where: episode.id in ^episode_ids,
      select: {episode.id, season.tv_series_id}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp poster_urls_by_owner([]), do: %{}

  defp poster_urls_by_owner(owners) do
    owners
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {owner_type, owner_ids} ->
      from(image in Image,
        where:
          image.owner_type == ^owner_type and image.owner_id in ^owner_ids and
            image.role == "poster",
        select: {image.owner_id, image.content_url}
      )
      |> Repo.all()
      |> Enum.map(fn {owner_id, content_url} ->
        {{owner_type, owner_id}, Image.web_path(content_url)}
      end)
    end)
    |> Map.new()
  end
end
