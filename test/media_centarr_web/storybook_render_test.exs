defmodule MediaCentarrWeb.StorybookRenderTest do
  @moduledoc """
  End-to-end render smoke for every storybook story. Catches the failure
  modes that `StorybookCompileTest` can't see:

  - **Render-time crashes** — `FunctionClauseError`, `KeyError`,
    `MatchError` raised when a variation's attributes hit the component's
    actual render path. Stories with literal data usually work the first
    time, but break later when the component contract tightens (typed
    attrs, required slots, struct-only inputs).
  - **Phoenix.Component attr-validation failures** — surface as 400/500
    in the response when `enable_expensive_runtime_checks: true` (set in
    config/test.exs) is honoured.

  Generates one HTTP test per story file. Asserts the catalog page
  returns a non-error status. Variations are rendered inline (or in
  iframes for `def container, do: :iframe`); the catalog request
  exercises Phoenix Storybook's variation-discovery + render path.
  """

  use MediaCentarrWeb.ConnCase, async: false

  story_files = Path.wildcard("storybook/**/*.story.exs")

  if story_files == [] do
    raise "StorybookRenderTest: no story files found — wildcard is wrong"
  end

  # Derive the URL from a story file path.
  # `storybook/detail/more_info/cast_grid.story.exs` → `/storybook/detail/more_info/cast_grid`
  defp story_url(path) do
    path
    |> String.replace_prefix("storybook/", "/storybook/")
    |> String.replace_suffix(".story.exs", "")
  end

  for path <- story_files do
    @tag path: path
    test "renders: #{path}", %{conn: conn} do
      url = story_url(unquote(path))
      response = get(conn, url)

      assert response.status in 200..299, """
      #{url} returned #{response.status} — story is broken.

      Response excerpt:
      #{String.slice(response.resp_body, 0, 500)}
      """
    end
  end
end
