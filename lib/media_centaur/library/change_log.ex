defmodule MediaCentaur.Library.ChangeLog do
  @moduledoc """
  Records library additions and removals as `ChangeEntry` records.

  Called from orchestrators (Inbound, EntityCascade), not from Ash changes.
  Prunes to the most recent 100 entries after each insert.
  """
  import Ecto.Query

  alias MediaCentaur.Library
  alias MediaCentaur.Library.ChangeEntry
  alias MediaCentaur.Repo

  @max_entries 100

  @doc """
  Records an entity addition. Call after successful entity creation.
  """
  def record_addition(entity) do
    create_entry(entity, :added)
  end

  @doc """
  Records an entity removal. Call before entity destruction (while data is still available).
  """
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
    Library.create_change_entry!(%{
      entity_id: entity.id,
      entity_name: entity.name,
      entity_type: entity.type,
      kind: kind
    })

    prune()
    :ok
  end
end
