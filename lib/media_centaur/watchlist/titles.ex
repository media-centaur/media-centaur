defmodule MediaCentaur.Watchlist.Titles do
  @moduledoc """
  What the store says about title intents (ADR-071). A title intent
  carries no TMDB fact beyond its identity; `attach/1` fills the virtual
  `title` of loaded records from the store's render snapshots in one
  query, so every surface that paints a listed title reads the same
  record every other surface does.

  A record whose title the store does not hold carries its **label**
  instead (`TitleIntent.label/1`): the name and year the record was
  written with, as a `TMDB.Title` with identity, name and year and no
  artwork. That is the Ignored record after the retention sweep — it
  references nothing, so the store lets its snapshot go — and any record
  between its first write and the store's first contact.
  """

  alias MediaCentaur.Watchlist.TitleIntent
  alias MediaCentaur.TMDB.Store

  @doc "Records with their stored title's snapshot attached."
  @spec attach([TitleIntent.t()]) :: [TitleIntent.t()]
  def attach([]), do: []

  def attach(intents) when is_list(intents) do
    snapshots = Store.snapshots(Enum.map(intents, &{&1.tmdb_id, &1.media_type}))

    Enum.map(intents, fn intent ->
      ref = {intent.tmdb_id, intent.media_type}
      %{intent | title: Map.get_lazy(snapshots, ref, fn -> TitleIntent.label(intent) end)}
    end)
  end

  @doc "One record with its stored title attached; nil passes through."
  @spec attach_one(TitleIntent.t() | nil) :: TitleIntent.t() | nil
  def attach_one(nil), do: nil
  def attach_one(%TitleIntent{} = intent), do: intent |> List.wrap() |> attach() |> hd()
end
