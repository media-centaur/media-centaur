defmodule MediaCentaur.Showcase.Stubs.TmdbFixturesTest do
  use MediaCentaur.Case, async: true

  import ExUnit.CaptureLog

  alias MediaCentaur.Showcase.Stubs.TmdbFixtures

  @base_url "https://api.themoviedb.org/3"

  # The "network" a record-mode request reaches on a miss.
  defp upstream_answering(status, body) do
    fn conn -> conn |> Plug.Conn.put_status(status) |> Req.Test.json(body) end
  end

  defp client(dir, opts) do
    {network, opts} = Keyword.pop(opts, :network, upstream_answering(500, %{"unexpected" => true}))

    [base_url: @base_url, plug: network, retry: false]
    |> Req.new()
    |> TmdbFixtures.attach([authored: Path.join(dir, "authored"), recorded: dir] ++ opts)
  end

  defp search(client, query) do
    Req.get(client, url: "/search/movie", params: [query: query, year: 1968, api_key: "secret-key"])
  end

  @tag :tmp_dir
  test "a recorded request is answered with its recorded status and body", %{tmp_dir: dir} do
    path = TmdbFixtures.fixture_path(dir, URI.parse("#{@base_url}/search/movie?year=1968&query=Movie+A"))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"status" => 200, "body" => %{"results" => [%{"id" => 7}]}}))

    assert {:ok, %{status: 200, body: %{"results" => [%{"id" => 7}]}}} =
             dir |> client(record: false) |> search("Movie A")
  end

  @tag :tmp_dir
  test "a recorded failure is answered as that failure", %{tmp_dir: dir} do
    path = TmdbFixtures.fixture_path(dir, URI.parse("#{@base_url}/movie/9"))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"status" => 500, "body" => %{"status_message" => "boom"}}))

    assert {:ok, %{status: 500}} = dir |> client(record: false) |> Req.get(url: "/movie/9")
  end

  @tag :tmp_dir
  test "an unrecorded request is a 404 and a warning naming the request, never the network",
       %{tmp_dir: dir} do
    log =
      capture_log(fn ->
        assert {:ok, %{status: 404}} = dir |> client(record: false) |> search("Movie B")
      end)

    assert log =~ "not recorded"
    assert log =~ "/search/movie"
    assert log =~ "Movie+B"
    refute log =~ "secret-key"
  end

  @tag :tmp_dir
  test "record mode writes an unrecorded 200 and serves it afterwards without the network",
       %{tmp_dir: dir} do
    movie_c = %{"id" => 3, "title" => "Movie C", "release_date" => "1968-01-01"}
    recording = client(dir, record: true, network: upstream_answering(200, %{"results" => [movie_c]}))
    assert {:ok, %{status: 200}} = search(recording, "Movie C")

    path = TmdbFixtures.fixture_path(dir, URI.parse("#{@base_url}/search/movie?query=Movie+C&year=1968"))

    assert %{"status" => 200, "body" => %{"results" => [%{"id" => 3}]}} =
             path |> File.read!() |> Jason.decode!()

    refute File.read!(path) =~ "secret-key"

    assert {:ok, %{body: %{"results" => [%{"id" => 3}]}}} =
             dir |> client(record: false) |> search("Movie C")
  end

  @tag :tmp_dir
  test "record mode never overwrites a fixture and never records a failure", %{tmp_dir: dir} do
    path = TmdbFixtures.fixture_path(dir, URI.parse("#{@base_url}/search/movie?query=Movie+D&year=1968"))
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"status" => 200, "body" => %{"results" => []}}))

    overwriting =
      client(dir, record: true, network: upstream_answering(200, %{"results" => [%{"id" => 4}]}))

    assert {:ok, %{body: %{"results" => []}}} = search(overwriting, "Movie D")

    failing = client(dir, record: true, network: upstream_answering(503, %{"status_message" => "down"}))
    assert {:ok, %{status: 503}} = search(failing, "Movie E")

    refute File.exists?(
             TmdbFixtures.fixture_path(
               dir,
               URI.parse("#{@base_url}/search/movie?query=Movie+E&year=1968")
             )
           )
  end

  @tag :tmp_dir
  test "a recorded search keeps only the results that are the searched title, so other films never reach the recording",
       %{tmp_dir: dir} do
    results = [
      %{"id" => 1, "title" => "Movie A", "release_date" => "1968-10-01"},
      %{"id" => 2, "title" => "Movie A", "release_date" => "2024-12-25"},
      %{"id" => 3, "title" => "Movie B", "release_date" => "1968-05-01"}
    ]

    recording =
      client(dir, record: true, network: upstream_answering(200, %{"results" => results, "page" => 1}))

    assert {:ok, %{status: 200}} = search(recording, "Movie A")

    path = TmdbFixtures.fixture_path(dir, URI.parse("#{@base_url}/search/movie?query=Movie+A&year=1968"))

    assert %{"body" => %{"results" => [%{"id" => 1}], "page" => 1}} =
             path |> File.read!() |> Jason.decode!()
  end

  @tag :tmp_dir
  test "an authored answer is read before a recorded one, and record mode never writes there",
       %{tmp_dir: dir} do
    url = URI.parse("#{@base_url}/search/movie?query=Movie+F&year=1968")

    for {root, id} <- [{Path.join(dir, "authored"), 1}, {dir, 2}] do
      path = TmdbFixtures.fixture_path(root, url)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, Jason.encode!(%{"status" => 200, "body" => %{"results" => [%{"id" => id}]}}))
    end

    assert {:ok, %{body: %{"results" => [%{"id" => 1}]}}} =
             dir |> client(record: false) |> search("Movie F")

    movie_g = %{"id" => 7, "title" => "Movie G", "release_date" => "1968-01-01"}
    recording = client(dir, record: true, network: upstream_answering(200, %{"results" => [movie_g]}))
    assert {:ok, %{status: 200}} = search(recording, "Movie G")

    refute File.exists?(
             TmdbFixtures.fixture_path(
               Path.join(dir, "authored"),
               URI.parse("#{@base_url}/search/movie?query=Movie+G&year=1968")
             )
           )

    assert File.exists?(
             TmdbFixtures.fixture_path(
               dir,
               URI.parse("#{@base_url}/search/movie?query=Movie+G&year=1968")
             )
           )
  end

  test "a request's fixture path ignores the credential and the query's order" do
    a =
      TmdbFixtures.fixture_path(
        "/f",
        URI.parse("#{@base_url}/search/tv?query=Show&api_key=x&first_air_date_year=1960")
      )

    b =
      TmdbFixtures.fixture_path(
        "/f",
        URI.parse("#{@base_url}/search/tv?first_air_date_year=1960&query=Show")
      )

    assert a == b
    assert String.starts_with?(a, "/f/3/search/tv/")
  end
end
