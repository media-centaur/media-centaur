defmodule MediaCentaur.Apps do
  use Boundary,
    deps: [MediaCentaur.Settings, MediaCentaur.Library],
    exports: [App]

  @moduledoc """
  Bounded context for the Apps launcher — user-curated external
  applications (Steam games, emulators, anything with a shell command)
  launched fire-and-forget from the UI.

  An `App` is a uniform row (see `MediaCentaur.Apps.App`); add-methods are
  importers that fill it at add time. Launching knows nothing about
  sources — one code path (`MediaCentaur.Apps.Launcher`).
  """

  import Ecto.Query

  alias MediaCentaur.Apps.App
  alias MediaCentaur.Repo

  @doc "All apps, alphabetical by name (case-insensitive)."
  @spec list_apps() :: [App.t()]
  def list_apps do
    Repo.all(from(a in App, order_by: fragment("lower(?)", a.name)))
  end

  @spec get_app!(Ecto.UUID.t()) :: App.t()
  def get_app!(id), do: Repo.get!(App, id)

  @doc """
  Adds an app. Idempotent per steam origin — re-adding an existing
  `%{"source" => "steam", "app_id" => id}` returns the existing app
  unchanged.
  """
  @spec add_app(map()) :: {:ok, App.t()} | {:error, Ecto.Changeset.t()}
  def add_app(attrs) do
    case existing_by_origin(attrs[:origin] || attrs["origin"]) do
      %App{} = existing -> {:ok, existing}
      nil -> attrs |> App.create_changeset() |> Repo.insert()
    end
  end

  @spec update_app(App.t(), map()) :: {:ok, App.t()} | {:error, Ecto.Changeset.t()}
  def update_app(%App{} = app, attrs) do
    app |> App.update_changeset(attrs) |> Repo.update()
  end

  @spec remove_app(App.t()) :: :ok
  def remove_app(%App{} = app) do
    Repo.delete(app)
    :ok
  end

  @doc "Steam app ids already added — the picker marks these."
  @spec added_steam_ids() :: MapSet.t(integer())
  def added_steam_ids do
    list_apps()
    |> Enum.filter(&(&1.origin["source"] == "steam"))
    |> MapSet.new(& &1.origin["app_id"])
  end

  defp existing_by_origin(%{"source" => "steam", "app_id" => app_id}) do
    Enum.find(list_apps(), fn app ->
      app.origin["source"] == "steam" and app.origin["app_id"] == app_id
    end)
  end

  defp existing_by_origin(_origin), do: nil
end
