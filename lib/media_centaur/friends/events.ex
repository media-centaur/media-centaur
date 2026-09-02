defmodule MediaCentaur.Friends.Events do
  @moduledoc """
  Typed events on `friends:updates`. The only `Topics.publish` in the
  Friends context (event chokepoint).
  """

  alias MediaCentaur.Topics

  defmodule IdentityChanged do
    @moduledoc "The install's identity was generated or replaced."
    @enforce_keys [:pubkey]
    defstruct [:pubkey]
    @type t :: %__MODULE__{pubkey: String.t()}
  end

  @type t :: IdentityChanged.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%IdentityChanged{} = event), do: publish({:identity_changed, event})

  defp publish(message), do: Topics.publish(Topics.friends_updates(), message)
end
