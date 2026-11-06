defmodule MediaCentaur.Profiles.Actor do
  @moduledoc """
  The profile that acted: proof that a person, not the system, made a
  write (ADR-082). Built only where a person is present — the web layer,
  from the session's profile, and playback, from the profile playing —
  and enforced there by Credo (MC0044, `ActorAtTheEdge`).

  A write that can become something said to other people — a rung
  change, a finished title — carries an actor, or `nil` when no person
  made it (a sweep, a job, a seed, a repair). `Activities.review/4`,
  `watched/3` and `listing/2` take nothing but an actor, so a write the
  system made never posts.

  The actor is not the owner. A watch-progress row's `profile_id` says
  whose viewing it is, whoever wrote it; the actor says a person did it
  just now.
  """

  @enforce_keys [:profile_id]
  defstruct [:profile_id]

  @type t :: %__MODULE__{profile_id: Ecto.UUID.t()}

  @doc "The actor for `profile_id`, the profile acting."
  @spec new(Ecto.UUID.t()) :: t()
  def new(profile_id) when is_binary(profile_id), do: %__MODULE__{profile_id: profile_id}
end
