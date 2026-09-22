defmodule MediaCentaur.Library.Views.ItemAvailability do
  @moduledoc """
  Sets availability on projection items and withholds the artwork that
  cannot be served.

  Whether an entry's artwork can be shown is decided here, once: the entry's
  media directory must be available (`Library.MediaFileAvailability`) and
  the file must be on disk (`Library.ImageCache.resolve_path/1`, the lookup
  the image server serves from). Every artwork URL a projection carries is
  therefore servable at the moment the projection is built. A page renders
  a nil URL as its placeholder and never emits a URL the image server cannot
  answer — not while a drive is unmounted, and not for a file that vanished
  after it landed. When the drive returns, the projection rebuilds on
  `:availability_changed` and the URLs come back through the same
  `library:views` broadcast every other library change takes — the
  disconnected render and the connected render of a page are both pure
  functions of the projection at their moment, so a drive mounting between
  them changes the DOM and the browser fetches
  (`docs/plans/2026-09-22-artwork-availability.md`).

  Files are only checked for available directories, so an unmounted path is
  never touched.

  Every projection whose items carry artwork calls `resolve/2` in both its
  refresh and its database-fallback read, so the two paths agree.
  """

  alias MediaCentaur.ImageFiles
  alias MediaCentaur.Library.ImageCache
  alias MediaCentaur.Library.MediaFileAvailability

  @doc """
  Sets `available?` on every item from the availability of its entity's
  media directory, nils the `artwork` fields of the unavailable ones, and
  nils any remaining artwork URL whose file is not on disk. One bulk
  availability read per call, then one file check per artwork URL.

  Options:

    * `:id` — the item field holding the entity id, or a function of the
      item returning it.
    * `:artwork` — the item fields holding artwork URLs (default `[]`).
  """
  @spec resolve([struct()], keyword()) :: [struct()]
  def resolve([], _opts), do: []

  def resolve(items, opts) do
    id_of = id_reader(Keyword.fetch!(opts, :id))
    artwork_fields = Keyword.get(opts, :artwork, [])

    availability =
      items
      |> Enum.map(id_of)
      |> Enum.uniq()
      |> MediaFileAvailability.available_for_ids()

    Enum.map(items, fn item ->
      if Map.get(availability, id_of.(item), true) do
        Enum.reduce(
          artwork_fields,
          %{item | available?: true},
          &Map.update!(&2, &1, fn url -> servable(url) end)
        )
      else
        Enum.reduce(artwork_fields, %{item | available?: false}, &Map.replace!(&2, &1, nil))
      end
    end)
  end

  # The URL as given when its file is on disk right now, nil otherwise. A
  # URL this route does not serve is left alone.
  defp servable(nil), do: nil

  defp servable(url) do
    case ImageFiles.relative_path(url) do
      nil -> url
      relative -> if ImageCache.resolve_path(relative), do: url
    end
  end

  defp id_reader(field) when is_atom(field), do: &Map.fetch!(&1, field)
  defp id_reader(fun) when is_function(fun, 1), do: fun
end
