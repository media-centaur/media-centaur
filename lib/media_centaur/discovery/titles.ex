defmodule MediaCentaur.Discovery.Titles do
  @moduledoc """
  What the store says about title intents (ADR-071). A title intent
  carries no TMDB fact beyond its identity; `attach/1` fills the virtual
  `title` of loaded records from the store's render snapshots in one
  query, so every surface that paints a listed title reads the same
  record every other surface does.

  A record whose title the store does not hold yet carries a **bare
  identity** — a `TMDB.Title` with only `tmdb_id` and `media_type` set —
  so the row renders, blank, until first contact lands and
  `{:tmdb_title_changed, ref}` has the surface reload. In the app that
  window is short: a title is listed from its detail, which the store
  already holds, or from a friend's entry, whose artwork warm
  first-contacts it at once.
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.TMDB.{Store, Title}

  @doc "Records with their stored title's snapshot attached."
  @spec attach([TitleIntent.t()]) :: [TitleIntent.t()]
  def attach([]), do: []

  def attach(intents) when is_list(intents) do
    snapshots = Store.snapshots(Enum.map(intents, &{&1.tmdb_id, &1.media_type}))

    Enum.map(intents, fn intent ->
      ref = {intent.tmdb_id, intent.media_type}
      %{intent | title: Map.get_lazy(snapshots, ref, fn -> bare(ref) end)}
    end)
  end

  @doc "One record with its stored title attached; nil passes through."
  @spec attach_one(TitleIntent.t() | nil) :: TitleIntent.t() | nil
  def attach_one(nil), do: nil
  def attach_one(%TitleIntent{} = intent), do: intent |> List.wrap() |> attach() |> hd()

  defp bare({tmdb_id, media_type}), do: %Title{tmdb_id: tmdb_id, media_type: media_type}
end
