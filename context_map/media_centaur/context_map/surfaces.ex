defmodule MediaCentaur.ContextMap.Surfaces do
  @moduledoc """
  For each web module, the LiveViews that reach it through module
  references, transitively. A component is a consumer; the LiveViews are
  where the consumer's behaviour is seen. Built from `Source.references`
  within `lib/media_centaur_web` only.
  """

  alias MediaCentaur.ContextMap.Source

  @doc "Maps every web module to the sorted LiveViews that reach it, a LiveView reaching itself."
  @spec index([Source.t()]) :: %{module() => [module()]}
  def index(sources) do
    web = Enum.filter(sources, &(&1.context == :web))

    live_views =
      MapSet.new(for %Source{live_view?: true, modules: [live_view | _]} <- web, do: live_view)

    reverse =
      for source <- web, from <- source.modules, to <- source.references, from != to, reduce: %{} do
        acc -> Map.update(acc, to, [from], &[from | &1])
      end

    for source <- web, module <- source.modules, into: %{} do
      surfaces =
        module
        |> reachers(reverse)
        |> Enum.filter(&MapSet.member?(live_views, &1))
        |> Enum.sort_by(&inspect/1)

      {module, surfaces}
    end
  end

  defp reachers(module, reverse),
    do: [module] |> reachers(reverse, MapSet.new([module])) |> MapSet.to_list()

  defp reachers([], _reverse, seen), do: seen

  defp reachers([module | rest], reverse, seen) do
    new = reverse |> Map.get(module, []) |> Enum.reject(&MapSet.member?(seen, &1)) |> Enum.uniq()
    reachers(new ++ rest, reverse, Enum.into(new, seen))
  end
end
