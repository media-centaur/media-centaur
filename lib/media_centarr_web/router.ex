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
      live "/", LibraryLive, :index
      live "/status", StatusLive, :index
      live "/settings", SettingsLive, :index
      live "/review", ReviewLive, :index
      live "/console", ConsolePageLive, :index
      live "/history", WatchHistoryLive, :index
      live "/download", AcquisitionLive, :index
      live "/download/auto-grabs", AutoGrabsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MediaCentarrWeb do
  #   pipe_through :api
  # end
end
