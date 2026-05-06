if Mix.env() in [:dev, :test] do
  defmodule MediaCentarrWeb.Storybook do
    @moduledoc """
    Phoenix Storybook backend — component catalog mounted in :dev (for
    interactive use) and :test (so storybook_render_test.exs can smoke
    each story URL end-to-end). Loads the same `app.css` the real UI
    uses, so components render with their real glass surfaces, theme
    tokens, and daisyUI variants. See [`docs/storybook.md`](../../docs/storybook.md)
    for philosophy and conventions.

    The env guard exists because `phoenix_storybook` is `only: [:dev, :test]` —
    `mix compile` in `:prod` would otherwise fail to find `PhoenixStorybook`.
    """

    use PhoenixStorybook,
      otp_app: :media_centarr,
      content_path: Path.expand("../../storybook", __DIR__),
      css_path: "/assets/css/app.css",
      sandbox_class: "media-centarr"
  end
end
