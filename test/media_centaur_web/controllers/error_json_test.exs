defmodule MediaCentaurWeb.ErrorJSONTest do
  use MediaCentaurWeb.ConnCase, async: true

  alias MediaCentaurWeb.ErrorJSON

  test "a status template renders the one error body" do
    assert ErrorJSON.render("404.json", %{}) == %{error: %{code: :not_found, message: "Not Found"}}

    assert ErrorJSON.render("500.json", %{}) ==
             %{error: %{code: :internal_server_error, message: "Internal Server Error"}}
  end
end
