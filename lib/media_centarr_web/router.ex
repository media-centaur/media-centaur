defmodule MediaCentarrWeb.Router do
  @moduledoc false
  use MediaCentarrWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MediaCentarrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MediaCentarrWeb do
    pipe_through :browser

    live_session :default do
      live "/", HomeLive, :index
      live "/console", ConsolePageLive, :index
      live "/download", AcquisitionLive, :index
      live "/history", WatchHistoryLive, :index
      live "/library", LibraryLive, :index
      live "/review", ReviewLive, :index
      live "/settings", SettingsLive, :index
      live "/status", StatusLive, :index
      live "/upcoming", UpcomingLive, :index
    end

    # Backward-compat redirect — bookmarks to the old auto-grabs page land
    # on the unified Downloads page where activity now lives. Kept for at
    # least one release after v0.24.0; safe to drop later.
    get "/download/auto-grabs", AcquisitionRedirectController, :auto_grabs
  end

  # Phoenix Storybook — dev-only component catalog. See docs/storybook.md.
  if Mix.env() == :dev do
    import PhoenixStorybook.Router

    scope "/" do
      storybook_assets()
    end

    scope "/", MediaCentarrWeb do
      pipe_through :browser
      live_storybook("/storybook", backend_module: MediaCentarrWeb.Storybook)
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MediaCentarrWeb do
  #   pipe_through :api
  # end
end
