defmodule MediaCentaur.TMDB.NewReleases do
  @moduledoc """
  The New Releases shelf membership: which movies recently became
  available at home in the US, in what order (campaign `discovery.md`).

  TMDB's answer to one question — `/discover/movie`, US digital releases
  (type 4) of the last 14 days with 20 votes or more, by popularity,
  the first 40 — kept the way the store keeps TMDB's answer per title
  (ADR-071): the ordered ids and the digital date each qualified with,
  nothing else. Everything drawn on the shelf comes from the store's
  record and the referenced artwork tier; the membership is what names
  the records and keeps them alive (`NewReleases.References`).

  `replace/1` rewrites the membership whole and publishes
  `{:new_releases_changed}` on `Topics.tmdb_new_releases/0`; the shelf
  refresh is its only writer. `members/0` and `refs/0` are the reads;
  opening the page reads the database only.
  """

  import Ecto.Query

  alias MediaCentaur.Repo
  alias MediaCentaur.TMDB.NewReleases.Member
  alias MediaCentaur.TMDB.Store
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

    Topics.publish(Topics.tmdb_new_releases(), {:new_releases_changed})
  end

  @doc "Subscribes the caller to `Topics.tmdb_new_releases/0`."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.tmdb_new_releases())
end
