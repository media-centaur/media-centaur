defmodule MediaCentaur.Capabilities do
  use Boundary, deps: [MediaCentaur.Settings]
  @behaviour MediaCentaur.Cache

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
  query layer over `MediaCentaur.Config` + `MediaCentaur.Settings.Entry`.
  Writers call `save_test_result/2` and `clear_test_result/1`, which
  persist through `Settings` and broadcast `:capabilities_changed` on
  `Topics.capabilities_updates/0` so subscribed LiveViews can refresh.
  """

  alias MediaCentaur.Settings
  alias MediaCentaur.Topics

  @type subject :: :tmdb | :prowlarr | :download_client | :usenet_download_client
  @type status :: :ok | :error
  @type info :: %{status: status(), tested_at: DateTime.t()}

  @cache_key {__MODULE__, :ready_flags}

  # Config keys whose values feed into compute_flags/0. A change to any of
  # them invalidates the cached readiness flags. Defined here so subscribe/0
  # and relevant?/1 can't drift apart.
  @capability_input_keys [
    :tmdb_api_key,
    :prowlarr_url,
    :prowlarr_api_key,
    :download_client_type,
    :download_client_url,
    :usenet_download_client_type,
    :usenet_download_client_url
  ]

  @doc """
  Worker-side subscription: subscribes the caller to all source topics
  whose events invalidate the cached readiness flags. Called once from
  `MediaCentaur.Cache.Worker.init/1`.

  Subscribes to:

    * `Topics.capabilities_updates/0` — `:capabilities_changed` from
      `save_test_result/2` and `clear_test_result/1`
    * `Topics.config_updates/0` — `{:config_updated, key, value}` from
      `Config.update/2` and `Config.load_runtime_overrides/0`; `relevant?/1`
      filters down to the keys in `@capability_input_keys`

  Per ADR-041, external consumers (LiveViews) MUST NOT use this —
  consumers subscribe to derived topics only via `subscribe_changes/0`.
  """
  @impl MediaCentaur.Cache
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.capabilities_updates())
    :ok = Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.config_updates())
    :ok
  end

  @doc """
  Consumer-facing subscription: subscribes the caller to the derived
  `Topics.capabilities_updates/0` topic only. Receives `:capabilities_changed`
  messages whenever the cache flips.

  This is the facade used by `MediaCentaurWeb.Live.CapabilitiesAware`
  and by any LiveView that needs to react to capability changes. Per
  ADR-041, consumers depend on view shape and not on source events, so
  they must use this — not `subscribe/0` (worker) and not
  `Phoenix.PubSub.subscribe/2` directly.
  """
  @spec subscribe_changes() :: :ok | {:error, term()}
  def subscribe_changes do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.capabilities_updates())
  end

  @doc "Filters PubSub messages relevant to this cache."
  @impl MediaCentaur.Cache
  def relevant?(:capabilities_changed), do: true

  def relevant?({:config_updated, key, _value}), do: key in @capability_input_keys

  def relevant?(_), do: false

  @spec tmdb_ready?() :: boolean()
  def tmdb_ready?, do: read_flags().tmdb

  @spec prowlarr_ready?() :: boolean()
  def prowlarr_ready?, do: read_flags().prowlarr

  @doc """
  True when **any** protocol slot has a configured, connection-tested
  download client. The two slots are independent — each needs its own
  passing test (`:download_client` for torrent, `:usenet_download_client`
  for usenet); one slot's test never vouches for the other.
  """
  @spec download_client_ready?() :: boolean()
  def download_client_ready?, do: read_flags().download_client

  @doc "Per-protocol-slot readiness: configured + its own connection test passed."
  @spec client_ready?(:torrent | :usenet) :: boolean()
  def client_ready?(:torrent), do: read_flags().torrent_client
  def client_ready?(:usenet), do: read_flags().usenet_client

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
  @impl MediaCentaur.Cache
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

    torrent_client =
      client_configured?(:download_client_type, :download_client_url) and
        last_test_ok?(:download_client)

    usenet_client =
      client_configured?(:usenet_download_client_type, :usenet_download_client_url) and
        last_test_ok?(:usenet_download_client)

    download_client = torrent_client or usenet_client

    %{
      tmdb: tmdb_configured?() and last_test_ok?(:tmdb),
      prowlarr: prowlarr,
      torrent_client: torrent_client,
      usenet_client: usenet_client,
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

  defp storage_key(:usenet_download_client), do: "acquisition:usenet_download_client:last_test"

  defp last_test_ok?(subject) do
    case load_test_result(subject) do
      %{status: :ok} -> true
      _ -> false
    end
  end

  defp tmdb_configured?, do: MediaCentaur.Secret.present?(MediaCentaur.Config.get(:tmdb_api_key))

  defp prowlarr_configured? do
    url = MediaCentaur.Config.get(:prowlarr_url)

    is_binary(url) and url != "" and
      MediaCentaur.Secret.present?(MediaCentaur.Config.get(:prowlarr_api_key))
  end

  defp client_configured?(type_key, url_key) do
    type = MediaCentaur.Config.get(type_key)
    url = MediaCentaur.Config.get(url_key)
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
    Phoenix.PubSub.broadcast(MediaCentaur.PubSub, Topics.capabilities_updates(), :capabilities_changed)
  end
end
