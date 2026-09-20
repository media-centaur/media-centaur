defmodule MediaCentaur.ReleaseTracking.Titles do
  @moduledoc """
  What the store says about tracked items (ADR-071). A tracked item
  carries no TMDB fact of its own; `attach/1` fills the virtual `name`
  and `season_sizes` of loaded items from their stored title and seasons
  in two queries, so every reader that shows a tracked title's name or
  plans against its season sizes reads one representation. An item whose
  title the store does not hold yet keeps them empty until
  `TMDB.CheckJob`'s next tick first-contacts it.

  `payload/1` is the acquisition path's read: the stored payload, first
  contact when the store lacks it, because a plan's identity must be
  right and a tracked title is a reference the app holds — first contact
  is not a check (ADR-071 §3).
  """

  alias MediaCentaur.ReleaseTracking.{Calendar, Item}
  alias MediaCentaur.TMDB.Store

  @doc "Items with their stored title's name and season sizes attached."
  @spec attach([Item.t()]) :: [Item.t()]
  def attach([]), do: []

  def attach(items) when is_list(items) do
    records = Store.get_many(Enum.map(items, &{&1.tmdb_id, &1.media_type}))

    seasons =
      items
      |> Enum.filter(&(&1.media_type == :tv_series))
      |> Enum.map(& &1.tmdb_id)
      |> case do
        [] -> %{}
        ids -> Store.seasons_for(ids)
      end

    today = Date.utc_today()

    Enum.map(items, fn item ->
      case Map.get(records, {item.tmdb_id, item.media_type}) do
        nil ->
          item

        record ->
          season_payloads = seasons |> Map.get(item.tmdb_id, []) |> Enum.map(& &1.payload)
          %{item | name: name(record), season_sizes: sizes(item, record, season_payloads, today)}
      end
    end)
  end

  @doc "One item with its stored title attached; nil passes through."
  @spec attach_one(Item.t() | nil) :: Item.t() | nil
  def attach_one(nil), do: nil
  def attach_one(%Item{} = item), do: item |> List.wrap() |> attach() |> hd()

  @doc "The stored payload behind a tracked item, first contact when the store lacks it."
  @spec payload(Item.t()) :: {:ok, map()} | {:error, term()}
  def payload(%Item{} = item) do
    with {:ok, record} <- Store.ensure({item.tmdb_id, item.media_type}) do
      {:ok, record.payload}
    end
  end

  defp name(%{media_type: :movie, payload: payload}), do: payload["title"]
  defp name(%{media_type: :tv_series, payload: payload}), do: payload["name"]

  defp sizes(%Item{media_type: :tv_series}, record, season_payloads, today),
    do: Calendar.season_sizes(record.payload, season_payloads, today)

  defp sizes(_item, _record, _season_payloads, _today), do: %{}
end
