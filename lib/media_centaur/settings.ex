defmodule MediaCentaur.Settings do
  @moduledoc """
  Cross-cutting key/value settings — logging toggles, framework log
  suppression, spoiler-free mode, service startup flags.

  Not library data; lives in its own bounded context.
  """

  alias MediaCentaur.Repo
  alias MediaCentaur.Settings.Entry
  alias MediaCentaur.Topics

  @type attrs :: %{optional(atom() | binary()) => term()}

  @doc "Subscribe the caller to settings change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.settings_updates())
  end

  def list_entries, do: {:ok, Repo.all(Entry)}
  def list_entries!, do: Repo.all(Entry)

  def get_by_key(key) do
    {:ok, Repo.get_by(Entry, key: key)}
  end

  @spec find_or_create_entry(attrs()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_entry(attrs) do
    key = attrs[:key] || attrs["key"]

    case Repo.get_by(Entry, key: key) do
      nil -> Entry.upsert_changeset(attrs) |> Repo.insert()
      existing -> Entry.update_changeset(existing, attrs) |> Repo.update()
    end
  end

  @spec find_or_create_entry!(attrs()) :: Entry.t()
  def find_or_create_entry!(attrs), do: bang!(find_or_create_entry(attrs))

  def create_entry(attrs) do
    Entry.create_changeset(attrs) |> Repo.insert()
  end

  def create_entry!(attrs), do: bang!(create_entry(attrs))

  def update_entry(entry, attrs) do
    Entry.update_changeset(entry, attrs) |> Repo.update()
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
