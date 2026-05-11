defmodule MediaCentarr.Capabilities do
  use Boundary, deps: [MediaCentarr.Settings]
  @behaviour MediaCentarr.Cache

  @moduledoc """
  Predicates that gate user-visible features on an explicit "Test
  Connection" pass for each external integration (TMDB, Prowlarr,
  qBittorrent / download client).

  A capability is **ready** when:

    1. The integration is configured (credentials present), AND
    2. The most recently persisted connection test for it succeeded.

  Saving any config field in a section clears that section's stored
  test result (handled by the settings page), so a non-stale `:ok`
  result is a strong signal that the integration is currently usable.

  Nothing here owns a GenServer or data table — the module is a pure
  query layer over `MediaCentarr.Config` + `MediaCentarr.Settings.Entry`.
  Writers call `save_test_result/2` and `clear_test_result/1`, which
  persist through `Settings` and broadcast `:capabilities_changed` on
  `Topics.capabilities_updates/0` so subscribed LiveViews can refresh.
  """

  alias MediaCentarr.Settings
  alias MediaCentarr.Topics

  @type subject :: :tmdb | :prowlarr | :download_client
  @type status :: :ok | :error
  @type info :: %{status: status(), tested_at: DateTime.t()}

  @cache_key {__MODULE__, :ready_flags}

  @doc "Subscribes the caller to capability-change broadcasts."
  @impl MediaCentarr.Cache
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.capabilities_updates())
  end

  @doc "Filters PubSub messages relevant to this cache."
  @impl MediaCentarr.Cache
  def relevant?(:capabilities_changed), do: true
  def relevant?(_), do: false

  @spec tmdb_ready?() :: boolean()
  def tmdb_ready?, do: read_flags().tmdb

  @spec prowlarr_ready?() :: boolean()
  def prowlarr_ready?, do: read_flags().prowlarr

  @spec download_client_ready?() :: boolean()
  def download_client_ready?, do: read_flags().download_client

  @doc """
  Returns true when the Acquisition feature surface is fully usable —
  both search (Prowlarr) and submit-to-client (download client) are
  configured and tested.

  This is the semantic gate for Acquisition-area UI (the Downloads nav
  item, the Acquisition page, the auto-grab pipeline). Consumers should
  prefer this over composing `prowlarr_ready?/0 and download_client_ready?/0`
  themselves so the semantic stays in one place.
  """
  @spec acquisition_ready?() :: boolean()
  def acquisition_ready?, do: read_flags().acquisition

  @doc """
  Recomputes the cached readiness flags and writes them to
  `:persistent_term`. Called once at boot by the cache worker and on
  every `:capabilities_changed` broadcast it observes. Direct callers
  (e.g. `save_test_result/2`) don't need to invoke this — the broadcast
  drives the refresh.
  """
  @impl MediaCentarr.Cache
  @spec refresh_cache() :: :ok
  def refresh_cache do
    :persistent_term.put(@cache_key, compute_flags())
    :ok
  end

  defp read_flags do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> compute_flags()
      flags -> flags
    end
  end

  defp compute_flags do
    prowlarr = prowlarr_configured?() and last_test_ok?(:prowlarr)
    download_client = download_client_configured?() and last_test_ok?(:download_client)

    %{
      tmdb: tmdb_configured?() and last_test_ok?(:tmdb),
      prowlarr: prowlarr,
      download_client: download_client,
      acquisition: prowlarr and download_client
    }
  end

  @spec load_test_result(subject()) :: info() | nil
  def load_test_result(subject) do
    case Settings.get_by_key(storage_key(subject)) do
      {:ok, %{value: value}} when is_map(value) -> parse(value)
      _ -> nil
    end
  end

  @spec save_test_result(subject(), status()) :: info()
  def save_test_result(subject, status) when status in [:ok, :error] do
    info = %{status: status, tested_at: DateTime.utc_now()}

    Settings.find_or_create_entry!(%{
      key: storage_key(subject),
      value: serialize(info)
    })

    broadcast_changed()
    info
  end

  @spec clear_test_result(subject()) :: :ok
  def clear_test_result(subject) do
    case Settings.get_by_key(storage_key(subject)) do
      {:ok, nil} ->
        :ok

      {:ok, entry} ->
        Settings.destroy_entry(entry)
        broadcast_changed()
        :ok
    end
  end

  # --- Internal ---

  defp storage_key(:tmdb), do: "capabilities:tmdb:last_test"
  defp storage_key(:prowlarr), do: "acquisition:prowlarr:last_test"
  defp storage_key(:download_client), do: "acquisition:download_client:last_test"

  defp last_test_ok?(subject) do
    case load_test_result(subject) do
      %{status: :ok} -> true
      _ -> false
    end
  end

  defp tmdb_configured?, do: MediaCentarr.Secret.present?(MediaCentarr.Config.get(:tmdb_api_key))

  defp prowlarr_configured? do
    url = MediaCentarr.Config.get(:prowlarr_url)

    is_binary(url) and url != "" and
      MediaCentarr.Secret.present?(MediaCentarr.Config.get(:prowlarr_api_key))
  end

  defp download_client_configured? do
    type = MediaCentarr.Config.get(:download_client_type)
    url = MediaCentarr.Config.get(:download_client_url)
    is_binary(type) and type != "" and is_binary(url) and url != ""
  end

  defp parse(%{"status" => status, "tested_at" => iso})
       when status in ["ok", "error"] and is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} ->
        %{status: String.to_existing_atom(status), tested_at: datetime}

      _ ->
        nil
    end
  end

  defp parse(_), do: nil

  defp serialize(%{status: status, tested_at: %DateTime{} = tested_at}) do
    %{
      "status" => Atom.to_string(status),
      "tested_at" => DateTime.to_iso8601(tested_at)
    }
  end

  defp broadcast_changed do
    Phoenix.PubSub.broadcast(MediaCentarr.PubSub, Topics.capabilities_updates(), :capabilities_changed)
  end
end
