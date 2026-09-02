defmodule MediaCentaur.Friends do
  use Boundary,
    deps: [MediaCentaur.Nostr],
    exports: [Identity, Events, Events.IdentityChanged]

  @moduledoc """
  Bounded context for the friend network's configuration: this install's
  identity (`Friends.Identity`) and, in later layers, the relay list and
  the friend roster. Broadcasts typed events on `friends:updates`;
  subscribe through `subscribe/0`.
  """

  alias MediaCentaur.Topics

  @doc "Subscribe the caller to friends events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.friends_updates())
end
