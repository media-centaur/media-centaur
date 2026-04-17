defmodule MediaCentarr.UpdateChecker do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Queries GitHub Releases for the latest Media Centarr release and compares
  it against the running version.

  Uses `Req` with a base client cached in `:persistent_term`. The public
  `latest_release/1` function accepts an optional `%Req.Request{}` for
  test stubbing (see `test/media_centarr/update_checker_test.exs`).

  ## Endpoint

      GET https://api.github.com/repos/media-centarr/media-centarr/releases/latest

  The API is public; rate limit is 60 req/hour per IP without auth.
  """

  require MediaCentarr.Log, as: Log

  @base_url "https://api.github.com"
  @repo "media-centarr/media-centarr"

  @type release :: %{
          version: String.t(),
          tag: String.t(),
          published_at: DateTime.t(),
          html_url: String.t()
        }

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
  `{:error, {:http_error, status}}`, or `{:error, reason}` on transport
  failure.
  """
  @spec latest_release(Req.Request.t()) ::
          {:ok, release()}
          | {:error, :not_found | :malformed | {:http_error, integer()} | any()}
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
    with {:ok, published_at} <- parse_published_at(body["published_at"]) do
      {:ok,
       %{
         version: String.trim_leading(tag_name, "v"),
         tag: tag_name,
         published_at: published_at,
         html_url: body["html_url"] || ""
       }}
    end
  end

  defp parse_release(_), do: {:error, :malformed}

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
end
