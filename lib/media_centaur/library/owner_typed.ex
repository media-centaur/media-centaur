defmodule MediaCentaur.Library.OwnerTyped do
  @moduledoc """
  The contract a polymorphic Library record satisfies so `EntityCascade` can
  clear it when its owner is deleted.

  These records key on an `(owner_type, owner_id)` pair rather than a foreign
  key, because the owner can be any of several container types.
  `EntityCascade.delete_polymorphic/3` takes the schema as a *value* and asks
  it which owner types it accepts before deleting — so the module is known
  only at runtime and `owner_types/0` has no visible caller.

  Each implementor keeps its own list rather than deriving one from
  `Library.Containers.types/0`: the sets genuinely differ. `Image` also hangs
  off an `:episode`, `Extra` off a `:season`, and `MediaTrackOverride` only
  off the playable types. A shared list would have to be the union, which
  would let a record attach to an owner its table has no meaning for.

  Sibling of `MediaCentaur.Library.Writable`, which states the changeset
  contract for the same reason.
  """

  @doc "The owner types this record may attach to."
  @callback owner_types() :: [atom()]
end
