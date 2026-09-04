defmodule MediaCentaur.HttpClientTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.HttpClient

  test "an integration registered in the test config is routed through its Req.Test stub" do
    client = HttpClient.new(MediaCentaur.TMDB.Client, base_url: "https://example.test")
    assert client.options[:plug] == {Req.Test, :tmdb}
    assert client.options[:base_url] == "https://example.test"
  end

  test "an owner with no registered stub gets a plain Req client" do
    client = HttpClient.new(__MODULE__, retry: false)
    refute Keyword.has_key?(Map.to_list(client.options), :plug)
    assert client.options[:retry] == false
  end
end
