defmodule MediaCentaur.Showcase.StubsRouteTest do
  @moduledoc """
  In showcase mode every client `HttpClient.new/2` builds for a stubbed
  upstream is answered by its stand-in, with nothing configured and no
  `Req.Test` stub registered — so an answer here cannot have come from
  anywhere else.
  """
  use MediaCentaur.Case, async: false

  import ExUnit.CaptureLog

  alias MediaCentaur.Search.Prowlarr
  alias MediaCentaur.TMDB

  setup do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      Map.merge(config, %{showcase_mode: true, prowlarr_url: "http://localhost:9696"})
    )

    :ok
  end

  test "Prowlarr searches are answered by the showcase fixtures" do
    assert {:ok, results} = Prowlarr.search("anything")
    assert Enum.any?(results, &(&1.title =~ "Night.of.the.Living.Dead"))
  end

  test "an unrecorded TMDB search is answered not-found instead of reaching TMDB" do
    log =
      capture_log(fn ->
        assert {:error, {:http_error, 404, _body}} =
                 TMDB.Client.search_multi("Sample Show Never Recorded")
      end)

    assert log =~ "not recorded"
  end
end
