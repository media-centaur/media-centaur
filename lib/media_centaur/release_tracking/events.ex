defmodule MediaCentaur.ReleaseTracking.Events do
  @moduledoc """
  Typed payloads on `release_tracking:updates` (ADR-060). The topic's
  older messages are bare tuples (`{:releases_updated, ids}`,
  `{:item_removed, _, _}`, `{:tracking_sweep_completed}`); new messages
  are structs, one per module here, sent through `broadcast/1`.
  """

  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  defmodule TrackingStarted do
    @moduledoc """
    A person started tracking a title: a tracking item with `source:
    :manual` was created — from a search, a one-click download, or a
    hand-off. Items the library scan creates (`source: :library`) never
    send this; nobody acted.
    """
    @enforce_keys [:item_id, :title]
    defstruct [:item_id, :title]

    @type t :: %__MODULE__{item_id: Ecto.UUID.t(), title: Title.t()}
  end

  @type t :: TrackingStarted.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%TrackingStarted{} = event),
    do: Topics.publish(Topics.release_tracking_updates(), {:tracking_started, event})
end
