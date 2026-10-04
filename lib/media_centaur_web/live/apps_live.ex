defmodule MediaCentaurWeb.AppsLive do
  @moduledoc """
  The Apps launcher — a banner-card grid of user-curated external
  applications, launched fire-and-forget (`MediaCentaur.Apps`).

  Launch-only by default; the toolbar's Manage toggle reveals add /
  edit / remove. The Add modal has two tabs: the Steam picker (installed
  games discovered from the local Steam root, header art hotlinked from
  Steam's CDN at browsing tier — the artwork ladder's browsing tier
  downloads nothing) and the manual form (name, command, and — for a
  manual app — the banner: `Components.PictureField` at 460:215, cut
  on save into the 920×430 JPEG master and handed to
  `Apps.change_banner/2`; a Steam app's banner follows the store, so
  its edit has no picture field). Modal state
  lives in assigns — no URL params, so nothing for
  `data-nav-transient-params`.

  `?steam_root=` overrides `Steam.detect_root/0` (tests, nonstandard
  installs); an override pointing at a missing directory reads as
  "Steam not installed".
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Apps
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaur.Apps.App
  alias MediaCentaur.Apps.Steam
  alias MediaCentaur.ImageFiles
  alias MediaCentaurWeb.Components.AppCards
  alias MediaCentaurWeb.Components.PictureField

  # The banner master: Steam's current header size at 2×, the card's
  # 460:215 shape.
  @banner_size {920, 430}

  @impl true
  def mount(_params, _session, socket) do
    socket = Subscriptions.subscribe(socket, Apps)

    {:ok,
     socket
     |> assign(page_title: "Apps", manage: false, modal: :closed, add_tab: :steam)
     |> assign(steam_root_override: nil, steam_games: [], added_steam_ids: MapSet.new())
     |> assign(banner_removed?: false)
     |> allow_upload(:banner, PictureField.upload_options())
     |> assign_manual_form(App.create_changeset(%{}))
     |> load_apps()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :steam_root_override, params["steam_root"])}
  end

  @impl true
  def handle_event("launch_app", %{"app-id" => id}, socket) do
    app = Apps.get_app!(id)

    case Apps.launch(app) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Launching #{app.name}…")}

      {:error, :launcher_unavailable} ->
        {:noreply, put_flash(socket, :error, "Couldn't launch #{app.name} — setsid not found on PATH.")}
    end
  end

  def handle_event("toggle_manage", _params, socket) do
    {:noreply, assign(socket, manage: !socket.assigns.manage, modal: :closed)}
  end

  def handle_event("open_add", _params, socket) do
    {:noreply,
     socket
     |> assign(modal: :add, add_tab: :steam)
     |> reset_banner()
     |> assign_steam_games()
     |> assign_manual_form(App.create_changeset(%{}))}
  end

  def handle_event("set_add_tab", %{"tab" => tab}, socket) when tab in ~w(steam manual) do
    {:noreply, assign(socket, :add_tab, String.to_existing_atom(tab))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, socket |> assign(:modal, :closed) |> reset_banner()}
  end

  def handle_event("add_steam_game", %{"app-id" => raw_app_id}, socket) do
    steam_app_id = String.to_integer(raw_app_id)
    game = Enum.find(socket.assigns.steam_games, &(&1.app_id == steam_app_id))
    root = steam_root(socket)

    case root && game && Apps.add_steam_app(game, root) do
      {:ok, _app} ->
        {:noreply, socket |> load_apps() |> assign_steam_games()}

      _missing_or_error ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_app", %{"app-id" => id}, socket) do
    app = Apps.get_app!(id)

    {:noreply,
     socket
     |> assign(modal: {:edit, app})
     |> reset_banner()
     |> assign_manual_form(App.update_changeset(app, %{}))}
  end

  def handle_event("remove_app", %{"app-id" => id}, socket) do
    Apps.remove_app(Apps.get_app!(id))
    {:noreply, load_apps(socket)}
  end

  # The upload's change event: LiveView needs it bound to track the entry.
  def handle_event("validate_manual", _params, socket), do: {:noreply, socket}

  # Remove is pending until the save, as the profile picture's is.
  def handle_event("remove_banner", _params, socket),
    do: {:noreply, assign(socket, banner_removed?: true)}

  def handle_event("cancel_banner", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :banner, ref)}

  # The row is saved before the chosen image is consumed, so a name or
  # command error leaves the image pending for the next save.
  def handle_event("save_manual", %{"app" => app_params} = params, socket) do
    result =
      case socket.assigns.modal do
        {:edit, app} -> Apps.update_app(app, app_params)
        _add -> Apps.add_app(Map.put(app_params, "origin", %{"source" => "manual"}))
      end

    case result do
      {:ok, app} ->
        socket =
          socket |> assign(:modal, :closed) |> save_banner(app, PictureField.crop_from_params(params))

        {:noreply, socket |> assign(banner_removed?: false) |> load_apps()}

      {:error, changeset} ->
        {:noreply, assign_manual_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def handle_info({:app_artwork_changed, %Apps.Events.ArtworkChanged{}}, socket) do
    {:noreply, load_apps(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        modal_open?: assigns.modal != :closed,
        editing?: match?({:edit, _app}, assigns.modal),
        banner_app: banner_app(assigns.modal),
        steam_picker?:
          assigns.modal == :add and assigns.add_tab == :steam and
            is_list(assigns.steam_games) and assigns.steam_games != []
      )

    ~H"""
    <Layouts.app
      show_social={@show_social}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/apps"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <div class="relative" data-page-behavior="apps" data-nav-default-zone="apps">
        <div data-nav-zone="toolbar">
          <div class="flex items-baseline justify-between">
            <.page_header title="Apps" />
            <div class="flex items-center gap-2">
              <.button
                :if={@manage}
                variant="action"
                size="sm"
                phx-click="open_add"
                data-nav-item
                tabindex="0"
              >
                <.icon name="hero-plus" class="size-4" /> Add app
              </.button>
              <.button
                variant={if @manage, do: "secondary", else: "dismiss"}
                size="sm"
                phx-click="toggle_manage"
                data-nav-item
                tabindex="0"
              >
                <.icon
                  name={if @manage, do: "hero-check", else: "hero-cog-6-tooth"}
                  class="size-4"
                />
                {if @manage, do: "Done", else: "Manage"}
              </.button>
            </div>
          </div>
        </div>

        <.empty_state
          :if={@apps == []}
          id="apps-empty"
          icon="hero-rocket-launch"
          headline="Launch anything from here"
        >
          Add a Steam game or any command you want to reach without leaving the couch.
          <:action>
            <.button
              id="apps-empty-add"
              variant="primary"
              size="sm"
              phx-click="open_add"
              data-nav-item
              tabindex="0"
            >
              Add an app
            </.button>
          </:action>
        </.empty_state>

        <div :if={@apps != []} class="mt-4" data-nav-zone="grid">
          <div
            id="apps-grid"
            data-nav-grid
            class="grid gap-3 grid-cols-[repeat(auto-fill,minmax(230px,1fr))]"
          >
            <AppCards.banner_card
              :for={app <- @apps}
              id={"app-card-#{app.id}"}
              app_id={app.id}
              name={app.name}
              banner_url={app.banner_url}
              manage={@manage}
            />
          </div>
        </div>
      </div>

      <:overlays>
        <%!-- The Steam picker earns the full :md panel — a wide grid
              beats a two-column tower. Every other state (manual form,
              edit, no-Steam notices) stays a compact dialog. --%>
        <.modal
          id="apps-manage-modal"
          open={@modal_open?}
          dismiss={:persistent}
          on_close="close_modal"
          size={if @steam_picker?, do: :md, else: :sm}
          panel_class="p-5 space-y-4"
        >
          <div :if={@modal_open?}>
            <div class="space-y-4">
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-semibold">
                  {if @editing?, do: "Edit app", else: "Add app"}
                </h2>
                <.button
                  variant="dismiss"
                  size="sm"
                  shape="square"
                  phx-click="close_modal"
                  data-nav-item
                  tabindex="0"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </.button>
              </div>

              <div :if={@modal == :add} class="flex gap-1">
                <.button
                  variant={if @add_tab == :steam, do: "secondary", else: "dismiss"}
                  size="sm"
                  phx-click="set_add_tab"
                  phx-value-tab="steam"
                  data-nav-item
                  tabindex="0"
                >
                  Steam
                </.button>
                <.button
                  variant={if @add_tab == :manual, do: "secondary", else: "dismiss"}
                  size="sm"
                  phx-click="set_add_tab"
                  phx-value-tab="manual"
                  data-nav-item
                  tabindex="0"
                >
                  Manual
                </.button>
              </div>

              <div :if={@modal == :add && @add_tab == :steam} class="space-y-3">
                <p :if={@steam_games == :unavailable} class="text-sm text-base-content/55">
                  Steam wasn't found on this machine. Use the Manual tab to add any app by command.
                </p>
                <p :if={@steam_games == []} class="text-sm text-base-content/55">
                  Steam is installed, but no games were found.
                </p>
                <p
                  :if={is_list(@steam_games) && @steam_games != []}
                  class="text-sm text-base-content/55"
                >
                  Installed games from your Steam library. Adding one launches it through Steam.
                </p>
                <%!-- The vh cap divides by --ui-scale: the root zoom
                      multiplies vh, so a bare 60vh would overflow the
                      screen at >1× (same idiom as --modal-panel-h). --%>
                <div
                  :if={is_list(@steam_games) && @steam_games != []}
                  class="grid gap-2 grid-cols-3 max-h-[calc(60vh/var(--ui-scale,1))] overflow-y-auto thin-scrollbar"
                >
                  <.steam_tile
                    :for={game <- @steam_games}
                    game={game}
                    steam_root={@steam_root}
                    added?={MapSet.member?(@added_steam_ids, game.app_id)}
                  />
                </div>
              </div>

              <.form
                :if={@add_tab == :manual || @editing?}
                for={@manual_form}
                id="app-manual-form"
                phx-submit="save_manual"
                phx-change="validate_manual"
                class="space-y-3"
              >
                <.input field={@manual_form[:name]} label="Name" />
                <.input
                  field={@manual_form[:command]}
                  label="Command"
                  placeholder="e.g. minecraft-launcher"
                />
                <PictureField.picture_field
                  :if={@banner_app}
                  id="banner"
                  label="Banner"
                  noun="image"
                  upload={@uploads.banner}
                  aspect={{460, 215}}
                  removable?={@banner_app.banner_url != nil && !@banner_removed?}
                  remove_event="remove_banner"
                  cancel_event="cancel_banner"
                >
                  <:current>
                    <AppCards.banner_art
                      name={@banner_app.name}
                      banner_url={!@banner_removed? && @banner_app.banner_url}
                      class="w-32 shrink-0"
                    />
                  </:current>
                  <:preview>
                    <AppCards.banner_art name={@banner_app.name} class="w-32 shrink-0">
                      <canvas
                        data-role="preview"
                        width="460"
                        height="215"
                        class="absolute inset-0 size-full"
                      ></canvas>
                    </AppCards.banner_art>
                  </:preview>
                </PictureField.picture_field>
                <div class="flex justify-end gap-2">
                  <.button
                    variant="dismiss"
                    size="sm"
                    type="button"
                    phx-click="close_modal"
                    data-nav-item
                    tabindex="0"
                  >
                    Cancel
                  </.button>
                  <.button variant="primary" size="sm" type="submit" data-nav-item tabindex="0">
                    Save
                  </.button>
                </div>
              </.form>
            </div>
          </div>
        </.modal>
      </:overlays>
    </Layouts.app>
    """
  end

  attr :game, :map,
    required: true,
    doc: "a `Steam.game/0` map (`%{app_id, name}`) from `Steam.installed_games/1`"

  attr :steam_root, :string, required: true
  attr :added?, :boolean, required: true

  # One picker tile: banner art with the name below it — an overlay
  # fought the art (Steam headers carry their own logo lockups).
  # Added games keep their slot, dimmed and inert.
  defp steam_tile(assigns) do
    ~H"""
    <div
      id={"steam-tile-#{@game.app_id}"}
      data-steam-added={@added? && @game.app_id}
      phx-click={!@added? && "add_steam_game"}
      phx-value-app-id={!@added? && @game.app_id}
      class={[(@added? && "opacity-50") || "card-hover cursor-pointer"]}
      data-nav-item={!@added?}
      tabindex={!@added? && "0"}
    >
      <div class="relative aspect-[460/215] rounded-lg overflow-hidden glass-inset">
        <%!-- Tile art goes through SteamArtController: the local
              librarycache copy when present, CDN redirect otherwise.
              Hash-addressed titles 404 on any guessed CDN URL, so
              hotlinking broke their tiles. --%>
        <img
          src={~p"/apps/steam-art/#{@game.app_id}/banner?#{[root: @steam_root]}"}
          alt={@game.name}
          loading="lazy"
          decoding="async"
          class="absolute inset-0 w-full h-full object-cover"
        />
      </div>
      <p class="mt-1 truncate text-xs text-base-content/70">
        {@game.name}{if @added?, do: " — added"}
      </p>
    </div>
    """
  end

  # The card needs only these three fields; a plain map keeps the App
  # struct from growing view-only virtual fields.
  defp load_apps(socket) do
    apps =
      Enum.map(Apps.list_apps(), fn app ->
        %{id: app.id, name: app.name, banner_url: Apps.artwork_urls(app.id).banner_url}
      end)

    assign(socket, :apps, apps)
  end

  defp assign_steam_games(socket) do
    case steam_root(socket) do
      nil ->
        assign(socket, steam_games: :unavailable, steam_root: nil, added_steam_ids: MapSet.new())

      root ->
        assign(socket,
          steam_games: Steam.installed_games(root),
          steam_root: root,
          added_steam_ids: Apps.added_steam_ids()
        )
    end
  end

  # The app whose banner the form edits, as the field draws it: a new
  # manual app (nothing stored yet) or an edited manual app; nil for a
  # Steam app, whose banner follows the store.
  defp banner_app(:add), do: %{name: "", banner_url: nil}

  defp banner_app({:edit, %App{origin: %{"source" => "manual"}} = app}),
    do: %{name: app.name, banner_url: Apps.artwork_urls(app.id).banner_url}

  defp banner_app(_steam_or_closed), do: nil

  # What the save does with the banner (`Apps.banner_change/0`): the
  # chosen file becomes the master, cut at the person's rectangle, else
  # the centre; Remove means none, neither means keep. The entry is
  # consumed either way, so a file libvips cannot open leaves nothing
  # pending — the row is saved and the flash says the image was not. A
  # rejected entry is dropped first (`PictureField.drop_rejected/2`).
  defp save_banner(socket, app, crop) do
    socket = PictureField.drop_rejected(socket, :banner)

    masters =
      consume_uploaded_entries(socket, :banner, fn %{path: path}, _entry ->
        case ImageFiles.jpeg_master(path, @banner_size, crop: crop) do
          {:ok, bytes} -> {:ok, {:new, bytes}}
          {:error, _reason} -> {:ok, :bad_image}
        end
      end)

    change =
      case {masters, socket.assigns.banner_removed?} do
        {[:bad_image], _removed?} -> :bad_image
        {[{:new, bytes}], _removed?} -> {:new, bytes}
        {[], true} -> :none
        {[], false} -> :keep
      end

    case change != :bad_image && Apps.change_banner(app, change) do
      :ok -> socket
      {:error, :not_manual} -> socket
      _unreadable -> put_flash(socket, :error, "Saved, but that file is not an image we can read")
    end
  end

  # A closed or reopened form starts with nothing chosen and no Remove
  # pending.
  defp reset_banner(socket) do
    socket.assigns.uploads.banner.entries
    |> Enum.reduce(socket, &cancel_upload(&2, :banner, &1.ref))
    |> assign(banner_removed?: false)
  end

  defp assign_manual_form(socket, changeset) do
    assign(socket, :manual_form, to_form(changeset, as: :app))
  end

  # An explicit override is authoritative: pointing it at a missing
  # directory reads as "Steam not installed" rather than falling back to
  # a detected real install (determinism for tests and misconfigurations).
  defp steam_root(socket) do
    case socket.assigns.steam_root_override do
      nil -> Steam.detect_root()
      override -> if File.dir?(override), do: override
    end
  end
end
