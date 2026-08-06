defmodule MediaCentaur.Library.Writes do
  @moduledoc """
  Idempotent write primitives shared by the Library's record modules.

  The ingestion pipeline reaches the library concurrently and repeatedly
  — the same season, episode, or progress row can be written by two
  processes at once, and the same payload can be replayed. These
  primitives make "find it or write it" safe under both conditions so
  each record module states its lookup key and nothing else.

  Read-then-write is inherently racy: two callers can both miss on the
  read and both reach the insert. Where the schema carries a unique
  index (`Season`, `Episode`), the loser's insert returns a
  unique-constraint `{:error, changeset}` and `find_or_insert_by/3`
  recovers by re-reading the winner's row — so concurrent ingest of the
  same record returns `{:ok, record}` for every caller instead of
  stranding the loser or, absent the index, creating a duplicate.
  """

  alias MediaCentaur.Repo

  @doc """
  Reads a record by `lookup` (field/value pairs), or `nil` when absent.

  `Repo.get_by(Schema, key: nil)` matches the first row whose key is
  NULL, silently corrupting partial-input requests. Any nil lookup value
  is therefore treated as "no match" so the caller falls through to an
  insert and the changeset surfaces the missing required field.
  """
  @spec existing_by(module(), keyword()) :: Ecto.Schema.t() | nil
  def existing_by(schema, lookup) do
    if !Enum.any?(lookup, fn {_key, value} -> is_nil(value) end) do
      Repo.get_by(schema, lookup)
    end
  end

  @doc """
  Finds an existing record by `lookup` or inserts one from `attrs` via
  `schema.create_changeset/1`. Returns the existing record unchanged on
  hit, and recovers from a concurrent insert by re-reading.
  """
  @spec find_or_insert_by(module(), keyword(), map()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def find_or_insert_by(schema, lookup, attrs) do
    case existing_by(schema, lookup) do
      nil ->
        case Repo.insert(schema.create_changeset(attrs)) do
          {:ok, record} ->
            {:ok, record}

          {:error, changeset} = error ->
            if unique_constraint_error?(changeset) do
              case existing_by(schema, lookup) do
                nil -> error
                existing -> {:ok, existing}
              end
            else
              error
            end
        end

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Finds an existing record by `lookup` and updates it via
  `schema.update_changeset/2`, or inserts one from `attrs`.

  Unlike `find_or_insert_by/3`, a hit is *written through* rather than
  returned unchanged — this is the shape progress upserts need.
  """
  @spec upsert_by(module(), keyword(), map()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def upsert_by(schema, lookup, attrs) do
    case existing_by(schema, lookup) do
      nil -> Repo.insert(schema.create_changeset(attrs))
      existing -> Repo.update(schema.update_changeset(existing, attrs))
    end
  end

  @doc """
  Deletes `record`, raising on failure, and returns `:ok`.

  Deletion bangs return `:ok`, not the deleted struct — the caller asked
  for the row to be gone, not handed back. This is deliberately
  asymmetric with the create/update bangs, which return the record.
  """
  @spec destroy!(Ecto.Schema.t()) :: :ok
  def destroy!(record) do
    Repo.bang!(Repo.delete(record))
    :ok
  end

  @doc """
  Reads `key` from an attrs map that may be keyed by atom or by string.

  Ingestion payloads arrive with string keys; internal callers build
  atom-keyed maps. Record modules shouldn't each re-derive that.
  """
  @spec attr(map() | keyword(), atom()) :: term()
  def attr(attrs, key) when is_atom(key) do
    attrs[key] || attrs[Atom.to_string(key)]
  end

  defp unique_constraint_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)
  end
end
