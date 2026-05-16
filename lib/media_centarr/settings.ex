defmodule MediaCentarr.Settings do
  use Boundary, deps: [], exports: [Entry]
  @behaviour MediaCentarr.Cache

  @moduledoc """
  Cross-cutting key/value settings — logging toggles, framework log
  suppression, spoiler-free mode, service startup flags.

  Not library data; lives in its own bounded context.

  ## Cache

  The entire Settings table mirrors into `:persistent_term` via the
  shared `MediaCentarr.Cache.Worker`. Reads (`get_by_key/1`,
  `get_by_keys/1`, `list_entries/0`) consult the cache first and fall
  back to the database when the cache hasn't been initialised — tests
  skip the cache child and exercise the live DB path.

  Writes (`create_entry/1`, `update_entry/2`, `find_or_create_entry/1`,
  `destroy_entry/1`) broadcast `{:setting_changed, key, value}` on
  `Topics.settings_updates/0`. The Cache.Worker observes those events
  and triggers a `refresh_cache/0`. Subscribers (LiveViews, derived
  caches like Capabilities/Controls) receive the same broadcast and
  react to the keys they care about. `value` is the entry's value map,
  or `nil` for a delete.
  """

  import Ecto.Query, only: [from: 2]

  alias MediaCentarr.Repo
  alias MediaCentarr.Settings.Entry
  alias MediaCentarr.Topics

  @type attrs :: %{optional(atom() | binary()) => term()}

  @cache_key {__MODULE__, :entries}

  @doc "Subscribe the caller to settings change events."
  @impl MediaCentarr.Cache
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.settings_updates())
  end

  @doc "Filters PubSub messages relevant to this cache."
  @impl MediaCentarr.Cache
  def relevant?({:setting_changed, _key, _value}), do: true
  def relevant?(_), do: false

  @doc """
  Reloads every Settings entry into `:persistent_term`. Called once at
  boot by the cache worker and on every `{:setting_changed, _, _}`
  broadcast. Stores a `%{key => Entry.t()}` map.
  """
  @impl MediaCentarr.Cache
  @spec refresh_cache() :: :ok
  def refresh_cache do
    entries = Map.new(Repo.all(Entry), fn entry -> {entry.key, entry} end)
    :persistent_term.put(@cache_key, entries)
    :ok
  end

  @spec list_entries() :: [Entry.t()]
  def list_entries do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> Repo.all(Entry)
      entries -> Map.values(entries)
    end
  end

  @spec get_by_key(String.t()) :: {:ok, Entry.t() | nil}
  def get_by_key(key) do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> {:ok, Repo.get_by(Entry, key: key)}
      entries -> {:ok, Map.get(entries, key)}
    end
  end

  @doc """
  Returns a map of `key => Entry` for all keys that exist. Single
  cache lookup when the cache is warm; falls back to a single SELECT
  with `WHERE key IN (?)` otherwise. Use this instead of calling
  `get_by_key/1` in a loop.
  """
  @spec get_by_keys([String.t()]) :: %{String.t() => Entry.t()}
  def get_by_keys(keys) when is_list(keys) do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset ->
        from(e in Entry, where: e.key in ^keys)
        |> Repo.all()
        |> Map.new(fn entry -> {entry.key, entry} end)

      entries ->
        Map.take(entries, keys)
    end
  end

  @spec find_or_create_entry(attrs()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_entry(attrs) do
    key = attrs[:key] || attrs["key"]

    result =
      case Repo.get_by(Entry, key: key) do
        nil -> Repo.insert(Entry.upsert_changeset(attrs))
        existing -> Repo.update(Entry.update_changeset(existing, attrs))
      end

    on_write(result)
    result
  end

  @spec find_or_create_entry!(attrs()) :: Entry.t()
  def find_or_create_entry!(attrs), do: Repo.bang!(find_or_create_entry(attrs))

  def create_entry(attrs) do
    attrs |> Entry.create_changeset() |> Repo.insert() |> tap(&on_write/1)
  end

  def create_entry!(attrs), do: Repo.bang!(create_entry(attrs))

  def update_entry(entry, attrs) do
    entry |> Entry.update_changeset(attrs) |> Repo.update() |> tap(&on_write/1)
  end

  def update_entry!(entry, attrs), do: Repo.bang!(update_entry(entry, attrs))

  def destroy_entry(entry) do
    case Repo.delete(entry) do
      {:ok, deleted} ->
        delete_cache(deleted.key)
        broadcast(deleted.key, nil)
        {:ok, deleted}

      other ->
        other
    end
  end

  def destroy_entry!(entry) do
    Repo.bang!(destroy_entry(entry))
    :ok
  end

  # Every Repo-write path goes through here: refresh the persistent_term
  # cache synchronously so a same-process read after the write sees the
  # new value, then broadcast for cross-process subscribers. Why: the
  # async Cache.Worker that listens to `:setting_changed` only refreshes
  # the cache after a PubSub round-trip; LiveView handlers that read
  # immediately after a write (e.g. `Config.watch_dirs_entries/0` inside
  # `refresh_probes/1`) used to hit the stale value, render an
  # unchanged list, and force the user to click again.
  defp on_write({:ok, %Entry{} = entry}) do
    put_cache(entry)
    broadcast(entry.key, entry.value)
  end

  defp on_write(_), do: :ok

  defp put_cache(%Entry{key: key} = entry) do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> :ok
      entries -> :persistent_term.put(@cache_key, Map.put(entries, key, entry))
    end
  end

  defp delete_cache(key) do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> :ok
      entries -> :persistent_term.put(@cache_key, Map.delete(entries, key))
    end
  end

  defp broadcast(key, value) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.settings_updates(),
      {:setting_changed, key, value}
    )
  end
end
