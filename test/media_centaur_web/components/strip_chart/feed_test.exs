defmodule MediaCentaurWeb.Components.StripChart.FeedTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.StripChart.Feed

  test "with_window replaces or adds the window query parameter" do
    assert Feed.with_window("http://localhost/status?subsystem=http", :"5h") ==
             "/status?subsystem=http&window=5h"

    assert Feed.with_window("http://localhost/status?subsystem=http&window=1h", :"1mo") ==
             "/status?subsystem=http&window=1mo"
  end

  test "window_from_params falls back to the default" do
    assert Feed.window_from_params(%{"window" => "1w"}, :"1h") == :"1w"
    assert Feed.window_from_params(%{"window" => "2h"}, :"1h") == :"1h"
    assert Feed.window_from_params(%{}, :"1h") == :"1h"
  end
end
