defmodule MediaCentaurWeb.Router do
  use MediaCentaurWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MediaCentaurWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MediaCentaurWeb do
    pipe_through :browser

    live_session :default do
      live "/", LibraryLive, :index
      live "/status", StatusLive, :index
      live "/settings", SettingsLive, :index
      live "/review", ReviewLive, :index
      live "/console", ConsolePageLive, :index
      live "/history", WatchHistoryLive, :index
      live "/search", SearchLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MediaCentaurWeb do
  #   pipe_through :api
  # end
end
