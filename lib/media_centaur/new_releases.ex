defmodule MediaCentaur.NewReleases do
  use Boundary,
    deps: [
      MediaCentaur.IntegrationAvailability,
      MediaCentaur.TMDB,
      MediaCentaur.TmdbArtwork
    ],
    exports: [Member, RefreshJob, TmdbReferences]

  @moduledoc """
  The New Releases shelf: which movies recently became available at home
  in the US, in what order (campaign `discovery.md`).

  TMDB's answer to one question — `/discover/movie`, US digital releases
  (type 4) of the last 14 days with 20 votes or more, by popularity, the
  first 40 — kept the way the store keeps TMDB's answer per title
  (ADR-071): the **membership**, the ordered ids and the digital date
  each qualified with, and nothing else. Everything drawn on the shelf
  comes from the store's record and the referenced artwork tier; the
  membership names the records and keeps them alive (`TmdbReferences`).

  `refresh/1` is the one reader of the discover query: it rewrites the
  membership whole (`replace/1`, which publishes `{:new_releases_changed}`
  on `Topics.new_releases_updates/0`) and then ensures each member's
  record and artwork in shelf order through `TmdbArtwork.ensure/2`, the
  one first contact (`Store.ensure/2` beneath it). It runs from
  `RefreshJob`, daily and once at boot. Opening the page reads `members/0`
  and the store only.

  A context of its own, above TMDB and the artwork tier: the artwork tier
  depends on TMDB, so a refresh that ensures artwork cannot live inside
  the TMDB context.
  """

  import Ecto.Query

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.NewReleases.Member
  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.Client
  alias MediaCentaur.TMDB.Store
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.Topics

  @window_days 14
  @min_vote_count 20
  @size 40

  @doc "How many days back the digital release window reaches."
  @spec window_days() :: pos_integer()
  def window_days, do: @window_days

  @doc "The vote-count floor a movie needs to qualify."
  @spec min_vote_count() :: pos_integer()
  def min_vote_count, do: @min_vote_count

  @doc "How many members the shelf holds at most."
  @spec size() :: pos_integer()
  def size, do: @size

  @doc "The membership in shelf order."
  @spec members() :: [Member.t()]
  def members do
    Repo.all(from(m in Member, order_by: [asc: m.position]))
  end

  @doc "The members' store refs, in shelf order."
  @spec refs() :: [Store.ref()]
  def refs, do: Enum.map(members(), &Member.ref/1)

  @doc """
  Replaces the membership with `entries`, `%{tmdb_id, digital_date}` maps
  in shelf order, in one transaction, and announces the change. A
  duplicate id keeps its first position.
  """
  @spec replace([%{tmdb_id: pos_integer(), digital_date: Date.t()}]) :: :ok
  def replace(entries) when is_list(entries) do
    now = DateTime.utc_now(:second)

    rows =
      entries
      |> Enum.uniq_by(& &1.tmdb_id)
      |> Enum.with_index(fn entry, position ->
        %{
          id: Ecto.UUID.generate(),
          tmdb_id: entry.tmdb_id,
          position: position,
          digital_date: entry.digital_date,
          inserted_at: now,
          updated_at: now
        }
      end)

    {:ok, :ok} =
      Repo.transact(fn ->
        Repo.delete_all(Member)
        Repo.insert_all(Member, rows)
        {:ok, :ok}
      end)

    Topics.publish(Topics.new_releases_updates(), {:new_releases_changed})
  end

  @doc """
  The shelf refresh: runs the discover query for the window ending
  `today`, rewrites the membership, then ensures each member's record and
  artwork in shelf order. Returns the member count. A discover request
  that fails leaves the membership as it was; an ensure that TMDB cannot
  answer mid-run answers from disk, and the check job and the next
  refresh pick the rest up.
  """
  @spec refresh(Date.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def refresh(%Date{} = today) do
    with {:ok, rows} <- discover(today) do
      entries = rows |> Enum.flat_map(&entry/1) |> Enum.uniq_by(& &1.tmdb_id) |> Enum.take(@size)
      :ok = replace(entries)
      Enum.each(entries, &TmdbArtwork.ensure(:movie, &1.tmdb_id))
      Log.info(:tmdb, "new releases refreshed — #{length(entries)} members")
      {:ok, length(entries)}
    end
  end

  @doc "Subscribes the caller to `Topics.new_releases_updates/0`."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.new_releases_updates())

  # The discover query, two pages at most: twenty rows a page, forty
  # members. A single page that already fills the shelf asks for no second.
  defp discover(today) do
    filters = [
      region: "US",
      release_type: 4,
      released_from: Date.add(today, -@window_days),
      released_to: today,
      min_vote_count: @min_vote_count
    ]

    with {:ok, %{results: first, total_pages: total_pages}} <-
           Client.discover_movies(filters ++ [page: 1]) do
      if total_pages > 1 and length(first) < @size do
        with {:ok, %{results: second}} <- Client.discover_movies(filters ++ [page: 2]) do
          {:ok, first ++ second}
        end
      else
        {:ok, first}
      end
    end
  end

  # With `region` set, a discover row's `release_date` is that region's
  # date of the requested type: the US digital date. A row without a
  # usable id or date is not a member.
  defp entry(%{"id" => id, "release_date" => date}) when is_integer(id) and id > 0 do
    case Date.from_iso8601(date || "") do
      {:ok, digital_date} -> [%{tmdb_id: id, digital_date: digital_date}]
      {:error, _reason} -> []
    end
  end

  defp entry(_row), do: []
end
