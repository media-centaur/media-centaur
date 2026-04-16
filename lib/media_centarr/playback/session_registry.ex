defmodule MediaCentarr.Playback.SessionRegistry do
  @moduledoc """
  Registry wrapper for active playback sessions, keyed by entity_id.

  Each MpvSession registers itself via `{:via, Registry, {SessionRegistry, entity_id}}`.
  This module provides convenience functions over the underlying Registry.

  All functions return safe defaults if the Registry is not yet started
  (e.g. during hot reload or early boot).
  """

  @doc "Returns a via-tuple for registering or looking up a session by entity_id."
  def via(entity_id), do: {:via, Registry, {__MODULE__, entity_id}}

  @doc "Returns the pid for a given entity_id, or nil."
  def lookup(entity_id) do
    case Registry.lookup(__MODULE__, entity_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Returns a list of `{entity_id, pid}` for all active sessions."
  def list do
    Registry.select(__MODULE__, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
  rescue
    ArgumentError -> []
  end

  @doc "Returns true if a session is active for the given entity_id."
  def active?(entity_id), do: lookup(entity_id) != nil
end
