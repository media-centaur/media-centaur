defmodule MediaCentarr.SelfUpdate.UpdateChecker do
  @moduledoc """
  Queries GitHub Releases for the latest Media Centarr release and compares
  it against the running version.

  Uses `Req` with a base client cached in `:persistent_term`. The public
  `latest_release/1` function accepts an optional `%Req.Request{}` for
  test stubbing (see `test/media_centarr/self_update/update_checker_test.exs`).

  ## Endpoint

      GET https://api.github.com/repos/media-centarr/media-centarr/releases/latest

  The API is public; rate limit is 60 req/hour per IP without auth.

  ## Tag validation

  The API's `tag_name` is never trusted verbatim. Every parsed tag must
  match a strict semver shape (`v<major>.<minor>.<patch>` with an
  optional `-<prerelease>` suffix composed of alphanumerics and dots).
  Anything else is rejected as `:invalid_tag` — this closes the door on
  tag-injection attacks that could smuggle shell metacharacters or
  path components when the tag is later interpolated into URLs or
  shell commands.
  """

  require MediaCentarr.Log, as: Log

  @base_url "https://api.github.com"
  @repo "media-centarr/media-centarr"
  @cache_ttl_ms :timer.minutes(5)
  @tag_regex ~r/^v\d+\.\d+\.\d+(-[A-Za-z0-9\.]+)?$/

  @type release :: %{
          version: String.t(),
          tag: String.t(),
          published_at: DateTime.t(),
          html_url: String.t(),
          body: String.t()
        }

  # Sanity cap on the release body to avoid surprise bloat if the
  # GitHub API ever returns something unreasonable. Realistic CHANGELOG
  # entries are <5KB; this gives 4x headroom.
  @body_byte_cap 20_000

  @type classification :: :update_available | :up_to_date | :ahead_of_release

  @doc """
  Returns the default `Req` client for the GitHub Releases API.
  Cached in `:persistent_term` after first call.
  """
  def default_client do
    case :persistent_term.get({__MODULE__, :client}, nil) do
      nil ->
        client = build_client()
        :persistent_term.put({__MODULE__, :client}, client)
        client

      client ->
        client
    end
  end

  defp build_client do
    Req.new(
      base_url: @base_url,
      headers: [
        {"accept", "application/vnd.github+json"},
        {"user-agent", "media-centarr"}
      ]
    )
  end

  @doc """
  Fetches the latest GitHub release and returns it as a normalized map.

  Returns `{:ok, release}`, `{:error, :not_found}`, `{:error, :malformed}`,
  `{:error, :invalid_tag}`, `{:error, {:http_error, status}}`, or
  `{:error, reason}` on transport failure.
  """
  @spec latest_release(Req.Request.t()) ::
          {:ok, release()}
          | {:error, :not_found | :malformed | :invalid_tag | {:http_error, integer()} | any()}
  def latest_release(client \\ default_client()) do
    Log.info(:system, "checking for updates — GitHub releases")

    case Req.get(client, url: "/repos/#{@repo}/releases/latest") do
      {:ok, %{status: 200, body: body}} ->
        parse_release(body)

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        Log.warning(:system, "update check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_release(%{"tag_name" => tag_name} = body) when is_binary(tag_name) do
    with :ok <- validate_tag(tag_name),
         {:ok, published_at} <- parse_published_at(body["published_at"]) do
      {:ok,
       %{
         version: String.trim_leading(tag_name, "v"),
         tag: tag_name,
         published_at: published_at,
         html_url: html_url(body),
         body: sanitize_body(body["body"])
       }}
    end
  end

  defp parse_release(_), do: {:error, :malformed}

  defp sanitize_body(nil), do: ""

  defp sanitize_body(text) when is_binary(text) do
    if byte_size(text) > @body_byte_cap do
      binary_part(text, 0, @body_byte_cap)
    else
      text
    end
  end

  defp sanitize_body(_), do: ""

  @doc """
  Validates that a tag string matches the strict release tag shape.

  Returns `:ok` or `{:error, :invalid_tag}`. Exposed so the Downloader
  and any shell-out paths can reuse the same gate before interpolating
  a tag into a URL or filesystem path.
  """
  @spec validate_tag(String.t()) :: :ok | {:error, :invalid_tag}
  def validate_tag(tag) when is_binary(tag) do
    if Regex.match?(@tag_regex, tag), do: :ok, else: {:error, :invalid_tag}
  end

  def validate_tag(_), do: {:error, :invalid_tag}

  # Only accept an `html_url` that looks like a GitHub release page for the
  # expected repo. Any other value (missing, wrong host, wrong repo) is
  # replaced with a constructed URL from the validated tag so the UI link
  # never navigates to an attacker-controlled host.
  defp html_url(%{"html_url" => url, "tag_name" => tag}) when is_binary(url) do
    expected_prefix = "https://github.com/#{@repo}/releases/"

    if String.starts_with?(url, expected_prefix) do
      url
    else
      "https://github.com/#{@repo}/releases/tag/#{tag}"
    end
  end

  defp html_url(%{"tag_name" => tag}), do: "https://github.com/#{@repo}/releases/tag/#{tag}"

  defp parse_published_at(nil), do: {:ok, DateTime.utc_now()}

  defp parse_published_at(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:ok, DateTime.utc_now()}
    end
  end

  @doc """
  Classifies a release relative to a local version string.

  - `:update_available` — remote is newer than local
  - `:up_to_date` — versions match
  - `:ahead_of_release` — local is newer than remote (dev/unreleased build)
  """
  @spec compare(release(), String.t()) :: classification() | :error
  def compare(%{version: remote}, local) do
    case MediaCentarr.Version.compare_versions(remote, local) do
      :gt -> :update_available
      :eq -> :up_to_date
      :lt -> :ahead_of_release
      :error -> :error
    end
  end

  @type cache_outcome :: {:ok, release()} | {:error, term()}

  @doc """
  Returns the cached outcome of the most recent update check if it is within
  the TTL window, otherwise `:stale`. The cache lives in `:persistent_term`
  so it is process-independent and survives LiveView session turnover.
  """
  @spec cached_latest_release() :: {:fresh, cache_outcome()} | :stale
  def cached_latest_release do
    case :persistent_term.get({__MODULE__, :cache}, nil) do
      %{result: result, cached_at: at} ->
        if System.monotonic_time(:millisecond) - at < @cache_ttl_ms do
          {:fresh, result}
        else
          :stale
        end

      nil ->
        :stale
    end
  end

  @doc "Records the outcome of an update check for later reuse within the TTL."
  @spec cache_result(cache_outcome()) :: :ok
  def cache_result(result) do
    :persistent_term.put({__MODULE__, :cache}, %{
      result: result,
      cached_at: System.monotonic_time(:millisecond)
    })

    :ok
  end

  @doc "Drops the cached outcome so the next caller sees `:stale`."
  @spec clear_cache() :: :ok
  def clear_cache do
    _ = :persistent_term.erase({__MODULE__, :cache})
    :ok
  end
end
