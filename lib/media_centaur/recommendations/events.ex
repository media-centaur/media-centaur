defmodule MediaCentaur.Recommendations.Events do
  @moduledoc """
  Typed payloads for the `recommendations:updates` topic (ADR-060): one
  struct per message, `@enforce_keys`, a single `broadcast/1`.
  """

  alias MediaCentaur.Topics

  defmodule Received do
    @moduledoc "A friend's recommendation landed. Subscribers reload the feed."
    @enforce_keys [:id, :author_pubkey]
    defstruct [:id, :author_pubkey]

    @type t :: %__MODULE__{id: Ecto.UUID.t(), author_pubkey: String.t()}
  end

  defmodule Sent do
    @moduledoc "This install recommended a title. Subscribers reload the sent list."
    @enforce_keys [:id]
    defstruct [:id]

    @type t :: %__MODULE__{id: Ecto.UUID.t()}
  end

  @type t :: Received.t() | Sent.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%Received{} = event), do: publish({:recommendation_received, event})
  def broadcast(%Sent{} = event), do: publish({:recommendation_sent, event})

  defp publish(message), do: Topics.publish(Topics.recommendations_updates(), message)
end
