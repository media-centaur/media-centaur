defmodule MediaCentarr.Settings do
  use Boundary,
    deps: [MediaCentarr.Library, MediaCentarr.Watcher],
    exports: [Entry, Admin]

  @moduledoc """
  Cross-cutting key/value settings — logging toggles, framework log
  suppression, spoiler-free mode, service startup flags.

  Not library data; lives in its own bounded context.
  """

  alias MediaCentarr.Repo
  alias MediaCentarr.Settings.Entry
  alias MediaCentarr.Topics

  @type attrs :: %{optional(atom() | binary()) => term()}

  @doc "Subscribe the caller to settings change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.settings_updates())
  end

  def list_entries, do: Repo.all(Entry)

  def get_by_key(key) do
    {:ok, Repo.get_by(Entry, key: key)}
  end

  @doc """
  Returns a map of `key => Entry` for all keys that exist in the DB.
  Keys not found in the DB are absent from the map. Single SELECT with
  `WHERE key IN (?)` — use this instead of calling `get_by_key/1` in a
  loop.
  """
  @spec get_by_keys([String.t()]) :: %{String.t() => Entry.t()}
  def get_by_keys(keys) when is_list(keys) do
    import Ecto.Query

    from(e in Entry, where: e.key in ^keys)
    |> Repo.all()
    |> Map.new(fn entry -> {entry.key, entry} end)
  end

  @spec find_or_create_entry(attrs()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_entry(attrs) do
    key = attrs[:key] || attrs["key"]

    case Repo.get_by(Entry, key: key) do
      nil -> Repo.insert(Entry.upsert_changeset(attrs))
      existing -> Repo.update(Entry.update_changeset(existing, attrs))
    end
  end

  @spec find_or_create_entry!(attrs()) :: Entry.t()
  def find_or_create_entry!(attrs), do: bang!(find_or_create_entry(attrs))

  def create_entry(attrs) do
    Repo.insert(Entry.create_changeset(attrs))
  end

  def create_entry!(attrs), do: bang!(create_entry(attrs))

  def update_entry(entry, attrs) do
    Repo.update(Entry.update_changeset(entry, attrs))
  end

  def update_entry!(entry, attrs), do: bang!(update_entry(entry, attrs))

  def destroy_entry(entry), do: Repo.delete(entry)

  def destroy_entry!(entry) do
    bang!(Repo.delete(entry))
    :ok
  end

  defp bang!({:ok, result}), do: result

  defp bang!({:error, %Ecto.Changeset{} = changeset}) do
    raise Ecto.InvalidChangesetError, changeset: changeset, action: changeset.action
  end

  defp bang!({:error, reason}), do: raise("operation failed: #{inspect(reason)}")
end
