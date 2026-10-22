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

  scope "/", MediaCentaurWeb do
    pipe_through :browser

    # CapabilitiesAware as a session-wide on_mount seeds `:tmdb_ready`,
    # `:prowlarr_ready`, `:download_client_ready`, `:acquisition_ready`
    # on every LiveView and re-assigns them when capabilities change.
    # The shared layout reads these assigns directly, so the nav stays
    # in sync without any LiveView opting in.
    live_session :default,
      on_mount: [
        # First, so its hooks run before any page's: the arm gesture's
        # "any other interaction disarms" rule must see every event.
        MediaCentaurWeb.Live.ArmGesture,
        # Where the socket is (the gate's second enforcement point): assigns
        # :player — :host, or the paired Players.Player — or halts the mount
        # with a redirect to the pairing page. Ahead of ProfileAware, so an
        # unpaired device never reaches the picker.
        MediaCentaurWeb.Live.PlayerAware,
        # The viewing layer: a remote player's page is its OSD. Subscribes to
        # the player's viewing stream and answers the layer's events.
        MediaCentaurWeb.Live.ViewingAware,
        # Who is watching (ADR-078): assigns :profile and :profiles, or
        # redirects the first handle_params to the picker.
        MediaCentaurWeb.Live.ProfileAware,
        # Which disclosures the user opened, for the ones no handler reads.
        MediaCentaurWeb.Live.DisclosureState,
        MediaCentaurWeb.Live.CapabilitiesAware,
        {MediaCentaurWeb.ShellBadges, :default},
        # The sidebar renders on every page, so its Social entry needs
        # `:show_social` seeded session-wide (and re-assigned live on
        # toggle) rather than per-LiveView.
        {MediaCentaurWeb.Live.SettingAware,
         {MediaCentaur.Settings.Preferences.SocialVisibility, :show_social, :setting_aware_show_social}},
        # Same deal for the Apps launcher entry.
        {MediaCentaurWeb.Live.SettingAware,
         {MediaCentaur.Settings.Preferences.AppsVisibility, :show_apps, :setting_aware_show_apps}}
      ] do
      live "/", HomeLive, :index
      # The picker (UIDR-053): the one view ProfileAware mounts without an
      # active profile instead of redirecting, so it can be the door.
      live "/profiles", ProfilesLive, :index
      live "/apps", AppsLive, :index
      live "/console", ConsolePageLive, :index
      live "/social", SocialLive, :feed
      live "/social/friends", SocialLive, :friends
      live "/social/friends/:key", SocialLive, :person
      live "/guide", GuideLive, :index
      live "/guide/:slug", GuideLive, :show
      live "/history", WatchHistoryLive, :index
      live "/incoming", IncomingLive, :index
      live "/library", LibraryLive, :index
      live "/episode-mapping", EpisodeMappingLive, :index
      live "/review", ReviewLive, :index
      live "/settings", SettingsLive, :index
      live "/setup", SetupLive, :index
      live "/status", StatusLive, :index
    end

    # The picker's tiles post here: a LiveView cannot write the session cookie.
    post "/profiles/:id/activate", ProfileController, :activate

    # The pairing page: the one page an unpaired LAN device reaches
    # (`Plugs.RemoteAccess` lets `/pair` through). A match writes the
    # player into the session cookie, which a LiveView cannot.
    get "/pair", PairingController, :show
    post "/pair", PairingController, :create

    # Steam picker artwork — local librarycache file or CDN redirect
    # (hash-addressed titles have no guessable CDN URL; see controller).
    get "/apps/steam-art/:app_id/:role", SteamArtController, :show
  end

  # Phoenix Storybook — dev component catalog (also mounted in :test so
  # storybook_render_test.exs can smoke each story URL end-to-end). See
  # docs/storybook.md.
  #
  # The dep is `only: [:dev, :test]` (its markdown renderer, MDEx, is a Rust
  # NIF we keep out of the release), so `import PhoenixStorybook.Router`
  # cannot appear as plain code here: Elixir expands both branches of a
  # module-level `if`, and importing a module that is not compiled in :prod
  # fails. `Code.eval_quoted/3` defers expansion of the quoted block to when
  # the branch actually runs, which is only in :dev and :test.
  if Mix.env() in [:dev, :test] do
    Code.eval_quoted(
      quote do
        import PhoenixStorybook.Router

        scope "/" do
          storybook_assets()
        end

        scope "/", MediaCentaurWeb do
          pipe_through :browser
          live_storybook("/storybook", backend_module: MediaCentaurWeb.Storybook)
        end
      end,
      [],
      __ENV__
    )
  end
end
