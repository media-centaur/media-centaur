defmodule MediaCentaur.Showcase.Stubs.TmdbFixtures do
  @moduledoc """
  The showcase's stand-in for the TMDB API: a `Req` plugin that answers
  each request from a recorded fixture file instead of the network.

  `MediaCentaur.Showcase.Stubs.attach/2` attaches it to every `:tmdb`
  client in showcase mode. The image CDN (`:tmdb_images`) is not stubbed —
  artwork is public, needs no key, and is too large to commit.

  ## Fixture files

  One file per request under `dir`, at `fixture_path/2`: the request's
  path, then its query with the credential (`api_key`) dropped and the
  rest sorted — the identity `MediaCentaur.HttpClient.Cache.Key` gives a
  GET. A file holds `{"status": …, "body": …}`, so a fixture can declare a
  failure as well as an answer.

  ## Modes

    * **Serving** (`record: false`) — a fixture answers the request and
      halts it. A request with no fixture is answered 404 and logged as a
      warning naming it; it never reaches the network.
    * **Recording** (`record: true`) — a fixture still answers when there
      is one. A request with none goes to TMDB, and a 200 answer is written
      as its fixture. An existing file is never overwritten, a failure
      is never recorded, and a search keeps only the results that are the
      catalogued title (`MediaCentaur.Showcase.CatalogMatch.qualifies?/3`). `mix seed.showcase --record-tmdb` runs a seed this
      way.
  """

  require MediaCentaur.Log, as: Log

  alias MediaCentaur.HttpClient.Cache.Key
  alias MediaCentaur.Showcase.CatalogMatch

  @excluded_params ["api_key"]

  @doc """
  Attaches the fixture steps to `request`. Options: `:dir` (the fixture
  root) and `:record` (boolean).
  """
  @spec attach(Req.Request.t(), keyword()) :: Req.Request.t()
  def attach(%Req.Request{} = request, opts) do
    dir = Keyword.fetch!(opts, :dir)
    record? = Keyword.fetch!(opts, :record)

    request
    |> Req.Request.put_private(:showcase_tmdb_fixtures, %{dir: dir, record?: record?})
    |> Req.Request.append_request_steps(showcase_tmdb_fixture: &answer/1)
    |> Req.Request.append_response_steps(showcase_tmdb_record: &record/1)
  end

  @doc "Where the fixture for a request to `url` lives under `dir`."
  @spec fixture_path(Path.t(), URI.t()) :: Path.t()
  def fixture_path(dir, %URI{} = url) do
    {_host, path, query} = Key.build(url, @excluded_params)
    name = if query == [], do: "_", else: URI.encode_query(query)
    Path.join([dir, String.trim_leading(path, "/"), name <> ".json"])
  end

  defp answer(request) do
    %{dir: dir, record?: record?} = Req.Request.get_private(request, :showcase_tmdb_fixtures)
    path = fixture_path(dir, request.url)

    case File.read(path) do
      {:ok, json} ->
        %{"status" => status, "body" => body} = Jason.decode!(json)
        {request, Req.Response.put_private(json_response(status, body), :showcase_tmdb_fixture, :served)}

      {:error, :enoent} when record? ->
        request

      {:error, :enoent} ->
        Log.warning(:tmdb, "showcase: TMDB request not recorded — #{describe(request.url)}")
        {request, json_response(404, %{"status_message" => "not recorded"})}
    end
  end

  defp record({request, %Req.Response{status: 200} = response}) do
    %{dir: dir, record?: record?} = Req.Request.get_private(request, :showcase_tmdb_fixtures)
    path = fixture_path(dir, request.url)

    if record? and Req.Response.get_private(response, :showcase_tmdb_fixture) != :served and
         not File.exists?(path) do
      File.mkdir_p!(Path.dirname(path))

      body = catalog_results_only(request.url, response.body)
      File.write!(path, Jason.encode_to_iodata!(%{"status" => 200, "body" => body}, pretty: true))

      Log.info(:tmdb, "showcase: recorded #{describe(request.url)}")
    end

    {request, response}
  end

  defp record(pair), do: pair

  # A search answers with every film sharing a name, remakes included. The
  # recording keeps only the results that are the catalogued title, so a
  # title outside the public-domain catalog never reaches the repository.
  defp catalog_results_only(%URI{path: path, query: query}, %{"results" => results} = body)
       when is_list(results) do
    if String.contains?(path, "/search/") do
      params = URI.decode_query(query || "")
      year = String.to_integer(params["year"] || params["first_air_date_year"])
      %{body | "results" => Enum.filter(results, &CatalogMatch.qualifies?(&1, params["query"], year))}
    else
      body
    end
  end

  defp catalog_results_only(_url, body), do: body

  defp json_response(status, body) do
    Req.Response.put_header(
      Req.Response.new(status: status, body: Jason.encode!(body)),
      "content-type",
      "application/json"
    )
  end

  defp describe(url) do
    {_host, path, query} = Key.build(url, @excluded_params)
    if query == [], do: path, else: path <> "?" <> URI.encode_query(query)
  end
end
