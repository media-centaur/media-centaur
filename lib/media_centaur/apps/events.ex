defmodule MediaCentaur.Apps.Events do
  @moduledoc """
  Typed payloads for the `apps:updates` topic (ADR-060): one struct per
  message, `@enforce_keys`, a single `broadcast/1`.
  """

  alias MediaCentaur.Topics

  defmodule ArtworkCached do
    @moduledoc """
    A role's artwork landed in the app-art cache. Steam adds fetch CDN
    art async when the local Steam cache has no named files (newer
    hashed-layout entries), so this can arrive after the page rendered
    the app — subscribers reload their cards.
    """
    @enforce_keys [:app_id, :role]
    defstruct [:app_id, :role]

    @type t :: %__MODULE__{app_id: Ecto.UUID.t(), role: :banner | :poster}
  end

  @type t :: ArtworkCached.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%ArtworkCached{} = event), do: publish({:app_artwork_cached, event})

  defp publish(message), do: Topics.publish(Topics.apps_updates(), message)
end
