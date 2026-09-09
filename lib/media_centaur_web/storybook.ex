if Mix.env() in [:dev, :test] do
  defmodule MediaCentaurWeb.Storybook do
    @moduledoc """
    Phoenix Storybook backend — component catalog mounted in :dev (for
    interactive use) and :test (so storybook_render_test.exs can smoke
    each story URL end-to-end). Loads the same `app.css` the real UI
    uses, so components render with their real glass surfaces, theme
    tokens, and daisyUI variants. See [`docs/storybook.md`](../../docs/storybook.md)
    for philosophy and conventions.

    `color_mode: true` puts a light/dark/system picker in the header, which
    toggles a `psb:dark` class on `<html>` for storybook's own chrome. It also
    adds a `dark` class to the sandbox for component previews, which is inert
    here — the app is dark-only (daisyUI `themes: false`, a single `dark`
    theme), so previews render dark in every mode by design.

    The env guard exists because `phoenix_storybook` is `only: [:dev, :test]` —
    `mix compile` in `:prod` would otherwise fail to find `PhoenixStorybook`.
    """

    use PhoenixStorybook,
      otp_app: :media_centaur,
      content_path: Path.expand("../../storybook", __DIR__),
      css_path: "/assets/css/app.css",
      sandbox_class: "media-centaur",
      color_mode: true
  end
end
