defmodule MediaCentaur.Activities.Events do
  @moduledoc """
  Typed payloads for the `activities:updates` topic (ADR-060): one
  struct per message, `@enforce_keys`, a single `broadcast/1`. Every
  payload carries the activity's `kind` so a subscriber that cares about
  one kind can filter without a read.
  """

  alias MediaCentaur.Activities.Activity
  alias MediaCentaur.Topics

  defmodule Received do
    @moduledoc "A friend's activity landed. Subscribers reload the feed."
    @enforce_keys [:id, :kind, :author_pubkey]
    defstruct [:id, :kind, :author_pubkey]

    @type t :: %__MODULE__{id: Ecto.UUID.t(), kind: Activity.kind(), author_pubkey: String.t()}
  end

  defmodule Sent do
    @moduledoc "This install published an activity. Subscribers reload the sent list."
    @enforce_keys [:id, :kind]
    defstruct [:id, :kind]

    @type t :: %__MODULE__{id: Ecto.UUID.t(), kind: Activity.kind()}
  end

  defmodule Deleted do
    @moduledoc "An activity was withdrawn — by this install or by the friend who sent it. Subscribers reload."
    @enforce_keys [:id, :kind, :author_pubkey]
    defstruct [:id, :kind, :author_pubkey]

    @type t :: %__MODULE__{id: Ecto.UUID.t(), kind: Activity.kind(), author_pubkey: String.t()}
  end

  @type t :: Received.t() | Sent.t() | Deleted.t()

  @spec broadcast(t()) :: :ok | {:error, term()}
  def broadcast(%Received{} = event), do: publish({:activity_received, event})
  def broadcast(%Sent{} = event), do: publish({:activity_sent, event})
  def broadcast(%Deleted{} = event), do: publish({:activity_deleted, event})

  defp publish(message), do: Topics.publish(Topics.activities_updates(), message)
end
