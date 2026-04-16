defmodule MediaCentarr.Library.ChangeLog do
  @moduledoc """
  Records library additions and removals as `ChangeEntry` records.

  Called from orchestrators (Inbound, EntityCascade).
  Prunes to the most recent 100 entries after each insert.
  """
  import Ecto.Query

  alias MediaCentarr.Library
  alias MediaCentarr.Library.ChangeEntry
  alias MediaCentarr.Repo

  @max_entries 100

  @doc """
  Records an entity addition. Call after successful entity creation.

  The 2-arity version accepts the entity type explicitly, for type-specific
  records (TVSeries, Movie, etc.) that don't have a `.type` field.
  """
  def record_addition(record, entity_type) do
    create_entry_with_type(record, entity_type, :added)
  end

  def record_addition(entity) do
    create_entry(entity, :added)
  end

  @doc """
  Records an entity removal. Call before entity destruction (while data is still available).
  """
  def record_removal(record, entity_type) do
    create_entry_with_type(record, entity_type, :removed)
  end

  def record_removal(entity) do
    create_entry(entity, :removed)
  end

  @doc """
  Deletes entries beyond the most recent #{@max_entries}.
  """
  def prune do
    all_entries = Library.list_recent_changes!(@max_entries + 50, nil)
    overflow = Enum.drop(all_entries, @max_entries)

    if overflow != [] do
      ids = Enum.map(overflow, & &1.id)
      from(c in ChangeEntry, where: c.id in ^ids) |> Repo.delete_all()
    end

    :ok
  end

  defp create_entry(entity, kind) do
    create_entry_with_type(entity, entity.type, kind)
  end

  defp create_entry_with_type(record, entity_type, kind) do
    Library.create_change_entry!(%{
      entity_id: record.id,
      entity_name: record.name,
      entity_type: entity_type,
      kind: kind
    })

    prune()
    :ok
  end
end
