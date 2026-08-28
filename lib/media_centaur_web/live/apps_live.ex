defmodule MediaCentaurWeb.AppsLive do
  @moduledoc """
  The Apps launcher — a banner-card grid of user-curated external
  applications, launched fire-and-forget (`MediaCentaur.Apps`).

  Launch-only by default; the toolbar's Manage toggle reveals add /
  edit / remove. The Add modal has two tabs: the Steam picker (installed
  games discovered from the local Steam root, header art hotlinked from
  Steam's CDN at browsing tier — the artwork ladder's browsing tier
  downloads nothing) and the manual form (name + command). Modal state
  lives in assigns — no URL params, so nothing for
  `data-nav-transient-params`.

  `?steam_root=` overrides `Steam.detect_root/0` (tests, nonstandard
  installs); an override pointing at a missing directory reads as
  "Steam not installed".
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Apps
  alias MediaCentaur.Apps.App
  alias MediaCentaur.Apps.Steam
  alias MediaCentaurWeb.Components.AppCards

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Apps", manage: false, modal: :closed, add_tab: :steam)
     |> assign(steam_root_override: nil, steam_games: [], added_steam_ids: MapSet.new())
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
     |> assign_steam_games()
     |> assign_manual_form(App.create_changeset(%{}))}
  end

  def handle_event("set_add_tab", %{"tab" => tab}, socket) when tab in ~w(steam manual) do
    {:noreply, assign(socket, :add_tab, String.to_existing_atom(tab))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, :closed)}
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
     |> assign_manual_form(App.update_changeset(app, %{}))}
  end

  def handle_event("remove_app", %{"app-id" => id}, socket) do
    Apps.remove_app(Apps.get_app!(id))
    {:noreply, load_apps(socket)}
  end

  def handle_event("save_manual", %{"app" => params}, socket) do
    result =
      case socket.assigns.modal do
        {:edit, app} -> Apps.update_app(app, params)
        _add -> Apps.add_app(Map.put(params, "origin", %{"source" => "manual"}))
      end

    case result do
      {:ok, _app} ->
        {:noreply, socket |> assign(:modal, :closed) |> load_apps()}

      {:error, changeset} ->
        {:noreply, assign_manual_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        modal_open?: assigns.modal != :closed,
        editing?: match?({:edit, _app}, assigns.modal)
      )

    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_watchlist={@show_watchlist}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/apps"
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      status_errors={assigns[:status_errors] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <div class="relative" data-page-behavior="apps" data-nav-default-zone="apps">
        <div data-nav-zone="toolbar">
          <div class="flex items-baseline justify-between">
            <h1 class="text-lg font-semibold">Apps</h1>
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

        <div
          :if={@apps == []}
          id="apps-empty"
          class="mt-4 glass-inset rounded-lg px-4 py-6 text-center text-sm text-base-content/40"
        >
          No apps yet. Open Manage to add a Steam game or any command.
        </div>

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
        <div class="modal-backdrop" data-state={if @modal == :closed, do: "closed", else: "open"}>
          <div class="modal-panel" phx-click-away={@modal_open? && "close_modal"}>
            <div :if={@modal_open?} class="p-5 space-y-4">
              <div class="flex items-center justify-between">
                <h2 class="text-lg font-semibold">
                  {if @editing?, do: "Edit app", else: "Add app"}
                </h2>
                <.button variant="dismiss" size="sm" shape="square" phx-click="close_modal">
                  <.icon name="hero-x-mark" class="size-4" />
                </.button>
              </div>

              <div :if={@modal == :add} class="flex gap-1">
                <.button
                  variant={if @add_tab == :steam, do: "secondary", else: "dismiss"}
                  size="sm"
                  phx-click="set_add_tab"
                  phx-value-tab="steam"
                >
                  Steam
                </.button>
                <.button
                  variant={if @add_tab == :manual, do: "secondary", else: "dismiss"}
                  size="sm"
                  phx-click="set_add_tab"
                  phx-value-tab="manual"
                >
                  Manual
                </.button>
              </div>

              <div :if={@modal == :add && @add_tab == :steam}>
                <p :if={@steam_games == :unavailable} class="text-sm text-base-content/50">
                  Steam wasn't found on this machine. Use the Manual tab to add any app by command.
                </p>
                <p :if={@steam_games == []} class="text-sm text-base-content/50">
                  Steam is installed, but no games were found.
                </p>
                <div
                  :if={is_list(@steam_games) && @steam_games != []}
                  class="grid gap-2 grid-cols-2 max-h-[50vh] overflow-y-auto thin-scrollbar"
                >
                  <%= for game <- @steam_games do %>
                    <div
                      :if={MapSet.member?(@added_steam_ids, game.app_id)}
                      data-steam-added={game.app_id}
                      class="relative aspect-[460/215] rounded-lg overflow-hidden glass-inset opacity-50"
                    >
                      <img
                        src={Steam.cdn_art_url(game.app_id, :banner)}
                        alt={game.name}
                        loading="lazy"
                        decoding="async"
                        class="absolute inset-0 w-full h-full object-cover"
                      />
                      <span class="absolute bottom-1 left-2 text-xs text-white text-on-image">
                        {game.name} — added
                      </span>
                    </div>
                    <div
                      :if={!MapSet.member?(@added_steam_ids, game.app_id)}
                      phx-click="add_steam_game"
                      phx-value-app-id={game.app_id}
                      class="card-hover relative aspect-[460/215] rounded-lg overflow-hidden glass-inset cursor-pointer"
                      data-nav-item
                      tabindex="0"
                    >
                      <img
                        src={Steam.cdn_art_url(game.app_id, :banner)}
                        alt={game.name}
                        loading="lazy"
                        decoding="async"
                        class="absolute inset-0 w-full h-full object-cover"
                      />
                      <span class="absolute bottom-1 left-2 text-xs text-white text-on-image">
                        {game.name}
                      </span>
                    </div>
                  <% end %>
                </div>
              </div>

              <.form
                :if={@add_tab == :manual || @editing?}
                for={@manual_form}
                id="app-manual-form"
                phx-submit="save_manual"
                class="space-y-3"
              >
                <.input field={@manual_form[:name]} label="Name" />
                <.input
                  field={@manual_form[:command]}
                  label="Command"
                  placeholder="e.g. minecraft-launcher"
                />
                <div class="flex justify-end gap-2">
                  <.button variant="dismiss" size="sm" type="button" phx-click="close_modal">
                    Cancel
                  </.button>
                  <.button variant="primary" size="sm" type="submit">Save</.button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </:overlays>
    </Layouts.app>
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
        assign(socket, steam_games: :unavailable, added_steam_ids: MapSet.new())

      root ->
        assign(socket,
          steam_games: Steam.installed_games(root),
          added_steam_ids: Apps.added_steam_ids()
        )
    end
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
