defmodule MediaCentaur.Discovery.Events do
  @moduledoc """
  Typed payloads for the `discovery:updates` topic (ADR-060): one struct
  per message, `@enforce_keys`, a single `broadcast/1`.
  """

  alias MediaCentaur.Topics

  defmodule ItemAdded do
    @moduledoc "A title joined the watchlist. Subscribers refresh their ref set / list."
    @enforce_keys [:item_id, :tmdb_id, :media_type]
    defstruct [:item_id, :tmdb_id, :media_type]

    @type t :: %__MODULE__{
            item_id: Ecto.UUID.t(),
            tmdb_id: integer(),
            media_type: :movie | :tv_series
          }
  end

  defmodule ItemRemoved do
    @moduledoc "A title left the watchlist. The row is already gone — subscribers drop the ref."
    @enforce_keys [:tmdb_id, :media_type]
    defstruct [:tmdb_id, :media_type]

    @type t :: %__MODULE__{tmdb_id: integer(), media_type: :movie | :tv_series}
  end

  @type t :: ItemAdded.t() | ItemRemoved.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%ItemAdded{} = event), do: publish({:watchlist_item_added, event})
  def broadcast(%ItemRemoved{} = event), do: publish({:watchlist_item_removed, event})

  defp publish(message), do: Topics.publish(Topics.discovery_updates(), message)
end
