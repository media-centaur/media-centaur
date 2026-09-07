defmodule MediaCentaur.Discovery.Events do
  @moduledoc """
  Typed payloads for the `discovery:updates` topic (ADR-060): one struct
  per message, `@enforce_keys`, a single `broadcast/1`.

  There is one message, because there is one thing that can happen to a
  title intent: its rung moves. Added, removed and re-graded were three
  names for that before the ladder replaced them; `rung: nil` is Off,
  which is the removal.
  """

  alias MediaCentaur.Discovery.TitleIntent
  alias MediaCentaur.Topics

  defmodule RungChanged do
    @moduledoc """
    A title's rung moved. `rung: nil` means it is Off — the record is
    already gone. Subscribers refresh whatever they derived from it.
    """
    @enforce_keys [:tmdb_id, :media_type, :rung]
    defstruct [:tmdb_id, :media_type, :rung]

    @type t :: %__MODULE__{
            tmdb_id: integer(),
            media_type: :movie | :tv_series,
            rung: TitleIntent.rung() | nil
          }
  end

  @type t :: RungChanged.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%RungChanged{} = event),
    do: Topics.publish(Topics.discovery_updates(), {:title_intent_changed, event})
end
