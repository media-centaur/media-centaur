defmodule MediaCentaur.Acquisition.ViewModels.Timeline.Resolver do
  @moduledoc """
  What an event's payload points at, resolved once per window.

  A target-scoped event names its target — `target_id`, or for a
  `download_started` row the client's `infohash`, which `Targets` pins on
  the target as `torrent_hash` — and this resolves that pointer to the
  release's title and the episodes the target covers. Built by
  `MediaCentaur.Acquisition.Pursuits.detail_for/1` from the same units and
  covering targets the coverage board draws, so History and the board read
  one set of facts. Pure; `empty/0` resolves nothing (tests, stories, an
  event with no pointer).
  """

  alias MediaCentaur.Format

  defstruct targets: %{}, hashes: %{}

  @type subject :: %{release: String.t() | nil, labels: [String.t()]}
  @type t :: %__MODULE__{
          targets: %{Ecto.UUID.t() => subject()},
          hashes: %{String.t() => Ecto.UUID.t()}
        }

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @doc "Builds from `[{target, [unit]}]` — each covering target with the units it covers."
  @spec new([{map(), [map()]}]) :: t()
  def new(covering) when is_list(covering) do
    targets =
      Map.new(covering, fn {target, units} ->
        {target.id,
         %{
           release: target.release_title,
           labels: units |> Enum.map(&unit_label/1) |> Enum.reject(&is_nil/1)
         }}
      end)

    hashes =
      for {%{torrent_hash: hash} = target, _units} <- covering, is_binary(hash), into: %{} do
        {hash, target.id}
      end

    %__MODULE__{targets: targets, hashes: hashes}
  end

  @doc "The subject an event payload points at, or nil."
  @spec lookup(t(), map() | nil) :: subject() | nil
  def lookup(%__MODULE__{targets: targets}, %{"target_id" => id}) when is_binary(id),
    do: Map.get(targets, id)

  def lookup(%__MODULE__{targets: targets, hashes: hashes}, %{"infohash" => hash})
      when is_binary(hash) do
    case Map.get(hashes, hash) do
      nil -> nil
      id -> Map.get(targets, id)
    end
  end

  def lookup(_resolver, _payload), do: nil

  # An episode reads as its code; a query-door unit as its label.
  defp unit_label(%{season_number: season, episode_number: episode}) when is_integer(season),
    do: Format.episode_label(season, episode)

  defp unit_label(%{label: label}) when is_binary(label) and label != "", do: label
  defp unit_label(_unit), do: nil
end
