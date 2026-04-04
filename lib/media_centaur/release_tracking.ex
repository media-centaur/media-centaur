defmodule MediaCentaur.ReleaseTracking do
  @moduledoc """
  Bounded context for tracking upcoming movie and TV releases via TMDB.

  Fully isolated from the Library context — owns its own tables, images,
  and TMDB extraction logic.
  """

  import Ecto.Query
  alias MediaCentaur.Repo
  alias MediaCentaur.ReleaseTracking.{Item, Release, Event}

  # --- Items ---

  def track_item(attrs) do
    Item.create_changeset(attrs) |> Repo.insert()
  end

  def track_item!(attrs) do
    Item.create_changeset(attrs) |> Repo.insert!()
  end

  def ignore_item(%Item{} = item) do
    Item.update_changeset(item, %{status: :ignored}) |> Repo.update()
  end

  def watch_item(%Item{} = item) do
    Item.update_changeset(item, %{status: :watching}) |> Repo.update()
  end

  def update_item(%Item{} = item, attrs) do
    Item.update_changeset(item, attrs) |> Repo.update()
  end

  def get_item(id), do: Repo.get(Item, id)

  def get_item_by_tmdb(tmdb_id, media_type) do
    Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type)
  end

  def delete_item(%Item{} = item) do
    Repo.delete(item)
  end

  def list_watching_items do
    from(i in Item,
      where: i.status == :watching,
      order_by: [asc: i.name],
      preload: [:releases]
    )
    |> Repo.all()
  end

  def list_all_items do
    from(i in Item, order_by: [asc: i.name], preload: [:releases])
    |> Repo.all()
  end

  def tracking_status({tmdb_id, media_type}) do
    case Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type) do
      nil -> nil
      item -> item.status
    end
  end

  # --- Releases ---

  def create_release(attrs) do
    Release.create_changeset(attrs) |> Repo.insert()
  end

  def create_release!(attrs) do
    Release.create_changeset(attrs) |> Repo.insert!()
  end

  def update_release(%Release{} = release, attrs) do
    Release.update_changeset(release, attrs) |> Repo.update()
  end

  def list_releases do
    all =
      from(r in Release,
        join: i in assoc(r, :item),
        where: i.status == :watching,
        order_by: [asc: r.air_date],
        preload: [:item]
      )
      |> Repo.all()

    upcoming = Enum.reject(all, & &1.released)
    released = Enum.filter(all, & &1.released)

    %{upcoming: upcoming, released: released}
  end

  def list_releases_for_item(item_id) do
    from(r in Release, where: r.item_id == ^item_id, order_by: [asc: r.air_date])
    |> Repo.all()
  end

  def delete_releases_for_item(item_id) do
    from(r in Release, where: r.item_id == ^item_id) |> Repo.delete_all()
  end

  # --- Events ---

  def create_event(attrs) do
    Event.create_changeset(attrs) |> Repo.insert()
  end

  def create_event!(attrs) do
    Event.create_changeset(attrs) |> Repo.insert!()
  end

  def list_recent_events(limit \\ 20) do
    from(e in Event,
      order_by: [{:desc, e.inserted_at}, {:desc, fragment("rowid")}],
      limit: ^limit
    )
    |> Repo.all()
  end

  # --- Bulk operations ---

  def mark_past_releases_as_released do
    today = Date.utc_today()

    from(r in Release,
      where: not is_nil(r.air_date) and r.air_date <= ^today and r.released == false
    )
    |> Repo.update_all(set: [released: true])
  end
end
