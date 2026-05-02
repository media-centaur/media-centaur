if Mix.env() == :dev do
  defmodule MediaCentarrWeb.Storybook do
    @moduledoc """
    Phoenix Storybook backend — dev-only component catalog.

    Mounted at `/storybook` only when `Mix.env() == :dev` (see Router). Loads
    the same `app.css` the real UI uses, so components render with their
    real glass surfaces, theme tokens, and daisyUI variants. See
    [`docs/storybook.md`](../../docs/storybook.md) for philosophy and
    conventions.

    Wrapped in `if Mix.env() == :dev` because `phoenix_storybook` is a
    dev-only dependency. Without the guard, `mix compile` in `:test` and
    `:prod` fails to find `PhoenixStorybook`.
    """

    use PhoenixStorybook,
      otp_app: :media_centarr,
      content_path: Path.expand("../../storybook", __DIR__),
      css_path: "/assets/css/app.css",
      sandbox_class: "media-centarr"
  end
end
