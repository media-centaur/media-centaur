defmodule MediaCentaur.Library.Views.ItemAvailability do
  @moduledoc """
  Sets availability on projection items and withholds the artwork of an
  unavailable one.

  Whether an entry's artwork can be shown is decided here, once, from
  `Library.MediaFileAvailability`, so every artwork URL a projection carries
  is servable at the moment the projection is built. A page renders a nil
  URL as its placeholder and never emits a URL the image server cannot
  answer. When the drive returns, the projection rebuilds on
  `:availability_changed` and the URLs come back through the same
  `library:views` broadcast every other library change takes — the
  disconnected render and the connected render of a page are both pure
  functions of the projection at their moment, so a drive mounting between
  them changes the DOM and the browser fetches
  (`docs/plans/2026-09-22-artwork-availability.md`).

  Every projection whose items carry artwork calls `resolve/2` in both its
  refresh and its database-fallback read, so the two paths agree.
  """

  alias MediaCentaur.Library.MediaFileAvailability

  @doc """
  Sets `available?` on every item from the availability of its entity's
  media directory and nils the `artwork` fields of the unavailable ones.
  One bulk availability read per call.

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
        %{item | available?: true}
      else
        Enum.reduce(artwork_fields, %{item | available?: false}, &Map.replace!(&2, &1, nil))
      end
    end)
  end

  defp id_reader(field) when is_atom(field), do: &Map.fetch!(&1, field)
  defp id_reader(fun) when is_function(fun, 1), do: fun
end
