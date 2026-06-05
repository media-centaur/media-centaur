defmodule MediaCentaurWeb.Router do
  @moduledoc false
  use MediaCentaurWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MediaCentaurWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MediaCentaurWeb.Plugs.SetupRedirect
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MediaCentaurWeb do
    pipe_through :browser

    # CapabilitiesAware as a session-wide on_mount seeds `:tmdb_ready`,
    # `:prowlarr_ready`, `:download_client_ready`, `:acquisition_ready`
    # on every LiveView and re-assigns them when capabilities change.
    # The shared layout reads these assigns directly, so the nav stays
    # in sync without any LiveView opting in.
    live_session :default,
      on_mount: [MediaCentaurWeb.Live.CapabilitiesAware, {MediaCentaurWeb.DiagnosticsBadge, :default}] do
      live "/", HomeLive, :index
      live "/console", ConsolePageLive, :index
      live "/download", AcquisitionLive, :index
      live "/history", WatchHistoryLive, :index
      live "/library", LibraryLive, :index
      live "/review", ReviewLive, :index
      live "/settings", SettingsLive, :index
      live "/setup", SetupLive, :index
      live "/status", StatusLive, :index
      live "/upcoming", UpcomingLive, :index
    end

    # Backward-compat redirect — bookmarks to the old auto-grabs page land
    # on the unified Downloads page where activity now lives. Kept for at
    # least one release after v0.24.0; safe to drop later.
    get "/download/auto-grabs", AcquisitionRedirectController, :auto_grabs
  end

  # Phoenix Storybook — dev component catalog (also mounted in :test so
  # storybook_render_test.exs can smoke each story URL end-to-end). See
  # docs/storybook.md.
  if Mix.env() in [:dev, :test] do
    import PhoenixStorybook.Router

    scope "/" do
      storybook_assets()
    end

    scope "/", MediaCentaurWeb do
      pipe_through :browser
      live_storybook("/storybook", backend_module: MediaCentaurWeb.Storybook)
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MediaCentaurWeb do
  #   pipe_through :api
  # end
end
