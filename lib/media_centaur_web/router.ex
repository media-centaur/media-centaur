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

  scope "/mcp" do
    forward "/", AshAi.Mcp.Router,
      tools: [
        # Library reads
        :read_entities,
        :read_entity_details,
        :read_entity_progress,
        :read_watched_files,
        :read_images,
        :read_incomplete_images,
        :find_by_tmdb_id,
        :read_watch_progress,
        :read_entity_watch_progress,
        :read_settings,
        # Library writes
        :create_entity,
        :set_entity_content_url,
        :destroy_entity,
        :link_file,
        :destroy_watched_file,
        :create_image,
        :clear_image_content_url,
        :destroy_image,
        :create_identifier,
        :destroy_identifier,
        :create_movie,
        :destroy_movie,
        :create_season,
        :destroy_season,
        :create_episode,
        :destroy_episode,
        :upsert_watch_progress,
        :mark_watch_completed,
        :upsert_setting,
        :destroy_setting,
        # Review
        :read_pending_files,
        :approve_pending_file,
        :dismiss_pending_file,
        :set_pending_file_match,
        :destroy_pending_file,
        :search_tmdb,
        # Generic actions (operations)
        :parse_filename,
        :resolve_playback,
        :trigger_scan,
        :measure_storage,
        :watcher_statuses,
        :serialize_entity,
        :clear_database,
        :refresh_cache,
        :retry_incomplete,
        :dismiss_incomplete
      ],
      protocol_version_statement: "2024-11-05",
      otp_app: :media_centaur
  end

  scope "/", MediaCentaurWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/operations", OperationsLive, :index
    live "/review", ReviewLive, :index
    live "/library", LibraryLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MediaCentaurWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:media_centaur, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MediaCentaurWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
