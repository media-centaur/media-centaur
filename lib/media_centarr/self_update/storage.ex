defmodule MediaCentarr.SelfUpdate.Storage do
  @moduledoc """
  Durable storage for SelfUpdate state — `last_check_at` and `latest_known`
  release metadata — persisted via `MediaCentarr.Settings.Entry`.

  The `:persistent_term` cache owned by `UpdateChecker` is the hot-path
  data source for the UI; this module is its durable backing so the UI
  survives BEAM restarts without a fresh HTTP round-trip.

  ## Keys

    * `update.last_check_at` — ISO8601 string, only written on successful checks.
    * `update.latest_known` — map with `version`, `tag`, `published_at`,
      `html_url`, `body_excerpt` (truncated at save time to 500 chars).
  """

  alias MediaCentarr.Settings
  alias MediaCentarr.SelfUpdate.UpdateChecker

  @last_check_key "update.last_check_at"
  @latest_known_key "update.latest_known"
  @body_excerpt_limit 500

  @type release_record :: %{
          version: String.t(),
          tag: String.t(),
          published_at: DateTime.t(),
          html_url: String.t(),
          body_excerpt: String.t()
        }

  @doc """
  Persists a release + classification as the latest known check result.
  Truncates `body_excerpt` at save time.
  """
  @spec put_latest_known(map(), UpdateChecker.classification()) :: :ok
  def put_latest_known(release, classification) do
    value = %{
      "version" => release.version,
      "tag" => release.tag,
      "published_at" => DateTime.to_iso8601(release.published_at),
      "html_url" => release.html_url,
      "body_excerpt" => truncate(Map.get(release, :body_excerpt, ""), @body_excerpt_limit),
      "classification" => Atom.to_string(classification)
    }

    Settings.find_or_create_entry!(%{key: @latest_known_key, value: value})
    :ok
  end

  @doc """
  Reads the persisted latest-known release.

  Returns `{:ok, %{release: release_record(), classification: atom()}}` or `:none`.
  """
  @spec get_latest_known() ::
          {:ok, %{release: release_record(), classification: UpdateChecker.classification()}}
          | :none
  def get_latest_known do
    case Settings.get_by_key(@latest_known_key) do
      {:ok, %{value: value}} when is_map(value) -> {:ok, decode_latest_known(value)}
      _ -> :none
    end
  end

  @doc "Persists the timestamp of the last successful check."
  @spec put_last_check_at(DateTime.t()) :: :ok
  def put_last_check_at(%DateTime{} = at) do
    Settings.find_or_create_entry!(%{
      key: @last_check_key,
      value: %{"at" => DateTime.to_iso8601(at)}
    })

    :ok
  end

  @doc """
  Reads the timestamp of the last successful check.
  """
  @spec get_last_check_at() :: {:ok, DateTime.t()} | :none
  def get_last_check_at do
    case Settings.get_by_key(@last_check_key) do
      {:ok, %{value: %{"at" => iso}}} when is_binary(iso) ->
        case DateTime.from_iso8601(iso) do
          {:ok, at, _offset} -> {:ok, at}
          _ -> :none
        end

      _ ->
        :none
    end
  end

  @doc """
  Populates the `:persistent_term` cache in `UpdateChecker` from the
  persisted `latest_known` entry. No-op when nothing is persisted.

  Called at app boot so the UI has data immediately.
  """
  @spec hydrate_cache() :: :ok
  def hydrate_cache do
    case get_latest_known() do
      {:ok, %{release: release}} -> UpdateChecker.cache_result({:ok, release})
      :none -> :ok
    end
  end

  @doc """
  Returns `true` when the last successful check is either missing or older
  than the given TTL (in milliseconds). Used to decide whether a boot-time
  check should be enqueued.
  """
  @spec stale?(pos_integer()) :: boolean()
  def stale?(ttl_ms \\ :timer.hours(6)) do
    case get_last_check_at() do
      :none ->
        true

      {:ok, at} ->
        age_ms = DateTime.diff(DateTime.utc_now(), at, :millisecond)
        age_ms >= ttl_ms
    end
  end

  defp decode_latest_known(value) do
    release = %{
      version: value["version"],
      tag: value["tag"],
      published_at: decode_published_at(value["published_at"]),
      html_url: value["html_url"] || "",
      body_excerpt: value["body_excerpt"] || ""
    }

    classification =
      case value["classification"] do
        "update_available" -> :update_available
        "up_to_date" -> :up_to_date
        "ahead_of_release" -> :ahead_of_release
        _ -> :up_to_date
      end

    %{release: release, classification: classification}
  end

  defp decode_published_at(nil), do: DateTime.utc_now()

  defp decode_published_at(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp truncate(nil, _), do: ""
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max)
end
