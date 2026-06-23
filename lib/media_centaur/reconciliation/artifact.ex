defmodule MediaCentaur.Reconciliation.Artifact do
  @moduledoc """
  A thing to be placed on the canonical spine — a file (and, once
  acquisition converges, a release candidate). It carries **claims**: the
  season/episode/title it asserts *about itself*. A claim is evidence,
  not truth — `claimed_season: 2` is what a release named the cour, never
  proof of which canonical episode the artifact is. Models read claims as
  ordering/corroboration; the canonical target is decided by
  reconciliation, not by the claim (reconciliation campaign).
  """

  @enforce_keys [:id]
  defstruct [:id, :claimed_season, :claimed_episode, :claimed_title]

  @type t :: %__MODULE__{
          id: String.t(),
          claimed_season: integer() | nil,
          claimed_episode: integer() | nil,
          claimed_title: String.t() | nil
        }
end
