defmodule MediaCentaur.Library.ChangeLog do
  @moduledoc """
  Records library additions and removals as `ChangeEntry` records.

  Called from orchestrators (Inbound, EntityCascade).
  Prunes to the most recent 100 entries after each insert.
  """
  import Ecto.Query

  alias MediaCentaur.Library
  alias MediaCentaur.Library.ChangeEntry
  alias MediaCentaur.Repo

  @max_entries 100

  @doc """
  Records an entity addition. Call after successful entity creation.

  The entity type is passed explicitly: the type-specific records
  (TVSeries, Movie, …) carry no `.type` field of their own.
  """
  def record_addition(record, entity_type) do
    create_entry_with_type(record, entity_type, :added)
  end

  @doc """
  Records an entity removal. Call before entity destruction (while data is still available).
  """
  def record_removal(record, entity_type) do
    create_entry_with_type(record, entity_type, :removed)
  end

  @doc """
  Deletes entries beyond the most recent #{@max_entries}.
  """
  def prune do
    all_entries = Library.ChangeLog.list_recent_changes(@max_entries + 50, nil)
    overflow = Enum.drop(all_entries, @max_entries)

    if overflow != [] do
      ids = Enum.map(overflow, & &1.id)
      Repo.delete_all(from(c in ChangeEntry, where: c.id in ^ids))
    end

    :ok
  end

  def create_change_entry(attrs) do
    Repo.insert(ChangeEntry.create_changeset(attrs))
  end

  def create_change_entry!(attrs), do: Repo.bang!(create_change_entry(attrs))

  def list_recent_changes(limit, since) do
    query =
      from(c in ChangeEntry,
        order_by: [{:desc, c.inserted_at}, {:desc, fragment("rowid")}],
        limit: ^limit
      )

    query =
      if since do
        from(c in query, where: c.inserted_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  defp create_entry_with_type(record, entity_type, kind) do
    create_change_entry!(%{
      entity_id: record.id,
      entity_name: record.name,
      entity_type: entity_type,
      kind: kind
    })

    prune()
    :ok
  end
end
