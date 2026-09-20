defmodule MediaCentaur.Library.Writable do
  @moduledoc """
  The changeset contract a Library record module must satisfy to be driven by
  the Library's generic write helpers.

  Several write paths take the schema as a *value* and call back into it, so
  the module is only known at runtime:

  | seam | calls |
  |---|---|
  | `Containers.create/2` | `schema(type).create_changeset/1` |
  | `Writes.find_or_insert_by/3` | `schema.create_changeset/1` |
  | `Writes.upsert_by/3` | `schema.create_changeset/1`, `schema.update_changeset/2` |
  | `Files.upsert_by_path/2` | `schema.create_changeset/1`, `schema.update_changeset/2` |

  Declaring the contract does three things prose could not: the compiler
  checks that an implementor actually defines `create_changeset/1`, a reader
  of a schema module can see why a function with no visible caller exists,
  and static analysis stops reporting these as uncalled — a dispatch on a
  variable module is invisible to a call-graph tracer, which is how
  `MediaCentaur.Library.Image.update_changeset/2` sat dead among eleven live
  look-alikes until 2026-09-17.

  `MediaCentaur.Library.ProgressTracker` is the same idea for the progress
  schemas and predates this module; it declares its own `create_changeset/1`
  and `update_changeset/2` alongside the progress-specific transitions, so
  `WatchProgress` and `ExtraProgress` implement that instead of this.

  Only `create_changeset/1` is required — it is the one every seam calls.
  A record that is never updated in place simply does not define the
  optional callback.
  """

  @doc "Builds the insert changeset from a plain attribute map."
  @callback create_changeset(attrs :: map()) :: Ecto.Changeset.t()

  @doc "Builds the in-place update changeset for an existing record."
  @callback update_changeset(record :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()

  @optional_callbacks update_changeset: 2
end
