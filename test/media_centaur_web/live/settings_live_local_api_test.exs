defmodule MediaCentaurWeb.SettingsLiveLocalApiTest do
  use MediaCentaurWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias MediaCentaur.Features
  alias MediaCentaurWeb.ApiKey

  @section "/settings?section=local-api"

  defp shown_key(view) do
    view
    |> element("#local-api-key")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
  end

  test "while the feature is off the section draws the off state", %{conn: conn} do
    {:ok, view, _html} = live_async!(conn, @section)

    refute has_element?(view, "#generate-api-key")
    assert render(view) =~ "Local API is off"
  end

  describe "while the feature is on" do
    setup do
      Features.set(:local_api, true)
      :ok
    end

    test "says where to find the API's OpenAPI document", %{conn: conn} do
      {:ok, _view, html} = live_async!(conn, @section)

      assert html =~ "/api/v1/openapi.json"
    end

    test "generating shows a key that works, once", %{conn: conn} do
      {:ok, view, _html} = live_async!(conn, @section)

      view |> element("#generate-api-key") |> render_click()
      assert ApiKey.valid?(shown_key(view))

      {:ok, reopened, _html} = live_async!(conn, @section)
      refute has_element?(reopened, "#local-api-key")
    end

    test "replacing a key takes a second press, and then only the new key works", %{conn: conn} do
      first = ApiKey.generate()
      {:ok, view, _html} = live_async!(conn, @section)

      view |> element("#replace-api-key") |> render_click()
      assert ApiKey.valid?(first)

      view |> element("#replace-api-key") |> render_click()
      refute ApiKey.valid?(first)
      assert ApiKey.valid?(shown_key(view))
    end
  end
end
