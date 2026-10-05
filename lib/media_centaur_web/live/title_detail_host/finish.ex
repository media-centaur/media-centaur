defmodule MediaCentaurWeb.Live.TitleDetailHost.Finish do
  @moduledoc """
  What a host does when a playback session ends (UIDR-052). A standalone
  movie the session completed opens its title with the finish prompt —
  in place when its detail is already open, otherwise by opening it.
  Everything else leaves the page as it was (play in place, UIDR-027).

  A standalone movie is its own entity, so the session's entity is the
  completed movie. A movie in a collection plays under the collection's
  entity and does not match: the primary delete there would remove the
  whole collection.
  """

  @type reaction :: :ignore | {:open, String.t()} | {:in_place, String.t()}

  @doc """
  The host's reaction to a `SessionEnded` payload (map-matched, as every
  `playback:events` subscriber does), given the entity id of the open
  detail (nil when none is open) and whether the preference is on.
  """
  @spec reaction(%{entity_id: String.t(), completed: MapSet.t()}, String.t() | nil, boolean()) ::
          reaction()
  def reaction(%{entity_id: id, completed: completed}, open_entity_id, enabled?) do
    cond do
      not enabled? -> :ignore
      not MapSet.member?(completed, {:movie, id}) -> :ignore
      open_entity_id == id -> {:in_place, id}
      true -> {:open, id}
    end
  end
end
