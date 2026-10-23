defmodule MediaCentaur.Playback.SessionRegistry do
  @moduledoc """
  Registry wrapper for active playback sessions, keyed by
  `{player, entity_id}`: the player a viewing shows on (`:host`, or a
  paired player's id) and the entity it is a viewing of. One entity can
  play on two players at once; one player plays one entity at a time by
  its own nature, which `Sessions.play/2` enforces.

  Each MpvSession registers itself via `{:via, Registry, {SessionRegistry, key}}`.
  All functions return safe defaults if the Registry is not yet started
  (e.g. during hot reload or early boot).
  """

  @type key :: {MediaCentaur.Playback.player(), String.t()}

  @doc "Returns a via-tuple for registering or looking up a session by key."
  @spec via(key()) :: {:via, Registry, {__MODULE__, key()}}
  def via({_player, _entity_id} = key), do: {:via, Registry, {__MODULE__, key}}

  @doc "Returns the pid for a key, or nil."
  @spec lookup(key()) :: pid() | nil
  def lookup({_player, _entity_id} = key) do
    case Registry.lookup(__MODULE__, key) do
      [{pid, _}] -> pid
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Returns a list of `{key, pid}` for all active sessions."
  @spec list() :: [{key(), pid()}]
  def list do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  rescue
    ArgumentError -> []
  end

  @doc "Returns true if a session is active for the key."
  @spec active?(key()) :: boolean()
  def active?(key), do: lookup(key) != nil

  @doc "The sessions on one player, as `{key, pid}`."
  @spec on_player(MediaCentaur.Playback.player()) :: [{key(), pid()}]
  def on_player(player),
    do: Enum.filter(list(), fn {{session_player, _entity_id}, _pid} -> session_player == player end)
end
