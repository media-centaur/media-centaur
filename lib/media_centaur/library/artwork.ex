defmodule MediaCentaur.Library.Artwork do
  @moduledoc """
  Batch artwork-URL resolution by entity reference and role — the poster,
  the backdrop or the logo — for surfaces outside the Library views that
  need artwork for a heterogeneous list of entities (the Feed's rows, the
  Status page's recently-watched feed, the release rows on Incoming). The
  **library tier** of `MediaCentaur.TitleArtwork`'s ladder.

  Episodes resolve to their **series'** image in every role — episodes
  carry no poster, backdrop or logo of their own; a caller that already
  holds the series id passes `:tv_series` directly. The result map
  contains entries only for refs that resolved to a cached image; refs to
  deleted entities, or to entities without that role, are simply absent,
  so callers read with `Map.get(result, ref)` and treat `nil` as "no
  artwork".
  """

  import Ecto.Query

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.Episode
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Repo

  @type ref :: {:movie | :tv_series | :episode | :video_object, Ecto.UUID.t()}
  @type role :: String.t()

  @roles ~w(poster backdrop logo)

  @spec urls_by_refs([ref()], role()) :: %{ref() => String.t()}
  def urls_by_refs(refs, role) when role in @roles do
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

    urls = urls_by_owner(owners, role)

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

  defp urls_by_owner([], _role), do: %{}

  defp urls_by_owner(owners, role) do
    owners
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {owner_type, owner_ids} ->
      from(image in Image,
        where:
          image.owner_type == ^owner_type and image.owner_id in ^owner_ids and
            image.role == ^role,
        select: {image.owner_id, image.content_url}
      )
      |> Repo.all()
      |> Enum.map(fn {owner_id, content_url} ->
        {{owner_type, owner_id}, ImageFiles.web_path(content_url)}
      end)
    end)
    |> Map.new()
  end
end
