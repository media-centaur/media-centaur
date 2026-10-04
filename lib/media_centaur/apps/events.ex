defmodule MediaCentaur.Apps.Events do
  @moduledoc """
  Typed payloads for the `apps:updates` topic (ADR-060): one struct per
  message, `@enforce_keys`, a single `broadcast/1`.
  """

  alias MediaCentaur.Topics

  defmodule ArtworkChanged do
    @moduledoc """
    A role's artwork landed in, was replaced in, or was removed from the
    app-art cache: Steam adds fetch CDN art async when the local Steam
    cache has no named files (newer hashed-layout entries), a launch
    refreshes a Steam banner, and a manual app's banner is set or removed
    on save (`Apps.change_banner/2`) — subscribers reload their cards.
    """
    @enforce_keys [:app_id, :role]
    defstruct [:app_id, :role]

    @type t :: %__MODULE__{app_id: Ecto.UUID.t(), role: :banner | :poster}
  end

  @type t :: ArtworkChanged.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%ArtworkChanged{} = event), do: publish({:app_artwork_changed, event})

  defp publish(message), do: Topics.publish(Topics.apps_updates(), message)
end
