defmodule MediaCentaurWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """

  Module.register_attribute(__MODULE__, :storybook_status, persist: true)
  Module.register_attribute(__MODULE__, :storybook_reason, persist: true)
  @storybook_status :skip
  @storybook_reason "Page layouts, not catalog material"

  use MediaCentaurWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_path, :string, default: nil, doc: "the current request path for nav highlighting"

  attr :diagnostics_unseen, :integer,
    default: 0,
    doc: """
    Count of unseen auto-detected open incidents, rendered as a discovery
    badge on the Status nav item. Seeded app-wide by
    `MediaCentaurWeb.ShellBadges` (default `live_session` on_mount) and
    live-refreshed via the `shell:badges` derived topic.
    """

  attr :review_pending, :integer,
    default: 0,
    doc: """
    Count of files awaiting identity review (`Review.count_pending/0`).
    Together with `mapping_pending` it drives the sidebar Review entry:
    hidden when both are zero, badged with the sum otherwise, targeting
    /review while identity work exists and /reconcile when only mapping
    work remains. Seeded app-wide by `MediaCentaurWeb.ShellBadges`
    (default `live_session` on_mount) and live-refreshed via the
    `review:updates` PubSub topic.
    """

  attr :mapping_pending, :integer,
    default: 0,
    doc: """
    Count of files awaiting an episode-mapping decision
    (`Reconciliation.count_awaiting/0`). See `review_pending` — seeded by
    `MediaCentaurWeb.ShellBadges`, live-refreshed via the
    `reconciliation:updates` PubSub topic.
    """

  attr :status_errors, :integer,
    default: 0,
    doc: """
    Count of live error/critical buckets — the condition that turns a
    Status-page tile red. Rendered as a persistent red dot on the Status
    nav icon (visible in both the expanded and collapsed rail, unlike the
    `ml-auto` count badge which the 52px rail clips). Seeded app-wide by
    `MediaCentaurWeb.ShellBadges` and live-refreshed via the
    `shell:badges` derived topic. Unlike `diagnostics_unseen` it is not
    cleared by visiting /status — it stays until the errors are resolved
    or dismissed.
    """

  attr :show_watchlist, :boolean,
    default: false,
    doc: """
    Whether the sidebar shows the Watchlist entry — the `show_watchlist`
    preference (`MediaCentaur.Settings.Preferences.WatchlistVisibility`, default off
    while the feature is an opt-in preview). Seeded app-wide by the
    `SettingAware` on_mount in the default `live_session`; only the nav
    entry is gated — `/watchlist` stays reachable by URL.
    """

  attr :full_width, :boolean, default: false, doc: "when true, removes max-w-7xl constraint"

  slot :inner_block, required: true

  slot :overlays,
    doc: """
    Layout-level overlays — modals, dialogs, drawers — rendered as a sibling
    of `<main>`, OUTSIDE the spacing container.

    Why this exists: the content wrapper carries `space-y-4`, which applies
    `margin-bottom: 1rem` to every non-last child. CSS layout for a
    `position: fixed` element with both `top` and `bottom` set folds margins
    into the height calc — so a modal that ends up as a non-last child
    silently renders 16px shorter than the viewport, leaving an undimmed
    strip at the bottom of the page. Overlays placed in this slot escape
    the spacing container entirely and fill the viewport correctly.
    """

  def app(assigns) do
    ~H"""
    <div
      id="input-system"
      class="flex min-h-viewport"
      phx-hook="InputSystem"
      data-input-bindings={Jason.encode!(input_bindings())}
      data-global-bindings={Jason.encode!(global_bindings())}
    >
      <aside
        id="sidebar"
        class="sidebar glass-sidebar"
        data-nav-zone="sidebar"
        phx-hook="SidebarTooltip"
      >
        <div class="sidebar-group-label sidebar-label">Watch</div>
        <nav class="flex flex-col gap-0.5">
          <.link
            navigate="/"
            class={sidebar_link_class(@current_path, "/")}
            data-tip="Home"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-home" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Home</span>
          </.link>
          <.link
            navigate="/library"
            class={sidebar_link_class(@current_path, "/library")}
            data-tip="Library"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-book-open" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Library</span>
          </.link>
          <.link
            :if={@show_watchlist}
            navigate="/watchlist"
            class={sidebar_link_class(@current_path, "/watchlist")}
            data-tip="Watchlist"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-bookmark" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Watchlist</span>
          </.link>
          <%!-- One entry for the whole collection-growth story (DDR-015) —
                unconditional: without acquisition the page degrades to an
                honest forecast instead of disappearing. --%>
          <.link
            navigate="/incoming"
            class={sidebar_link_class(@current_path, "/incoming")}
            data-tip="Incoming"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-inbox-arrow-down" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Incoming</span>
          </.link>
        </nav>

        <div class="sidebar-group-label sidebar-label">System</div>
        <nav class="flex flex-col gap-0.5">
          <.link
            navigate="/status"
            class={sidebar_link_class(@current_path, "/status") <> " sidebar-link-system"}
            data-tip="Status"
            data-nav-item
            tabindex="0"
          >
            <span class="relative inline-flex flex-shrink-0">
              <.icon name="hero-squares-2x2" class="size-5" />
              <span
                :if={@status_errors > 0}
                id="sidebar-status-error-dot"
                class="absolute -top-0.5 -right-0.5 size-2 rounded-full bg-error"
                aria-hidden="true"
              />
            </span>
            <span class="sidebar-label">Status</span>
            <.badge :if={@diagnostics_unseen > 0} variant="error" size="xs" class="ml-auto">
              {@diagnostics_unseen}
            </.badge>
          </.link>
          <.link
            :if={@review_pending + @mapping_pending > 0}
            navigate={if @review_pending > 0, do: "/review", else: "/reconcile"}
            class={
              sidebar_link_class(@current_path, ["/review", "/reconcile"]) <>
                " sidebar-link-system"
            }
            data-tip="Review"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-document-text" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Review</span>
            <.badge variant="primary" size="xs" class="ml-auto">
              {@review_pending + @mapping_pending}
            </.badge>
          </.link>
          <.link
            navigate="/settings"
            class={sidebar_link_class(@current_path, "/settings") <> " sidebar-link-system"}
            data-tip="Settings"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-cog-6-tooth" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Settings</span>
          </.link>
        </nav>

        <div class="flex-1" />

        <button
          class="sidebar-link"
          phx-click={JS.dispatch("phx:toggle-sidebar")}
          data-tip="Expand"
        >
          <.icon
            name="hero-chevron-double-left"
            class="size-5 flex-shrink-0 sidebar-collapse-icon"
          />
          <span class="sidebar-label">Collapse</span>
        </button>
      </aside>

      <main class="flex-1 min-w-0 px-6 py-6 flex flex-col">
        <div class={["flex-1 min-h-0 space-y-4", !@full_width && "max-w-7xl"]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      {render_slot(@overlays)}
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the persistent console LiveView as a sticky child of the current page.
  Each page LiveView calls this once at the top of its render to mount the
  Guake-style dropdown console that survives navigation within the `:default`
  live_session.
  """
  attr :socket, :any, required: true

  def console_mount(assigns) do
    ~H"""
    {live_render(@socket, MediaCentaurWeb.ConsoleLive, id: "console-sticky", sticky: true)}
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <%!--
        User-action toasts auto-dismiss so a save → confirm flow never
        requires a manual click. Errors dwell a little longer; hovering or
        focusing either one pauses its countdown (see FlashAutoDismiss).
      --%>
      <.flash kind={:info} flash={@flash} dismiss_after={4000} />
      <.flash kind={:error} flash={@flash} dismiss_after={7000} />

      <%!--
        Disconnect toasts, in desktop-app voice: Media Centaur is a local
        app, not a website — the UI losing its backing service means the
        service is restarting, the machine just woke, or it was stopped.
        Never speak of "the internet", "the server", or "a connection".

        During a self-update reboot the WebSocket drops like any other
        disconnect, but it is expected — not an error. The LiveView sets
        `data-update-applying` on <html> while an update is in flight (see
        SettingsLive + app.js), so we suppress the red isn't-responding
        toasts and show the calm "Applying update" one instead. The
        `html:not([data-update-applying])` / `html[data-update-applying]`
        selectors gate which toast `show/1` actually un-hides on disconnect.
      --%>
      <%!-- The `to:` on remove_attribute must repeat the gate selector:
            a bare JS.remove_attribute targets the bound element
            UNconditionally, which once un-hid all three toasts on every
            disconnect (the "Applying update on every dev restart" bug —
            the gated show() was correct, the ungated unhide wasn't). --%>
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("Media Centaur isn't responding")}
        phx-disconnected={
          show("html:not([data-update-applying]) .phx-client-error #client-error")
          |> JS.remove_attribute("hidden",
            to: "html:not([data-update-applying]) .phx-client-error #client-error"
          )
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("It may be restarting — resuming automatically")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong")}
        phx-disconnected={
          show("html:not([data-update-applying]) .phx-server-error #server-error")
          |> JS.remove_attribute("hidden",
            to: "html:not([data-update-applying]) .phx-server-error #server-error"
          )
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Recovering automatically")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="update-applying"
        kind={:info}
        title={gettext("Applying update")}
        phx-disconnected={
          show("html[data-update-applying] #update-applying")
          |> JS.remove_attribute("hidden", to: "html[data-update-applying] #update-applying")
        }
        phx-connected={
          hide("#update-applying")
          |> JS.set_attribute({"hidden", ""})
          |> JS.remove_attribute("data-update-applying", to: "html")
        }
        hidden
      >
        {gettext("Installing the new version. This may take a moment.")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  attr :class, :string, default: nil

  slot :inner_block, required: true

  @doc """
  Mounts the input-system LiveView hook (keyboard/gamepad navigation) for a
  page that does NOT use `app/1` — currently just the standalone Setup tour,
  which has no sidebar. `app/1` renders its own `#input-system` root inline
  with the same hook + bindings; this is that mount factored out for the
  sidebar-less case. Only one `#input-system` element may exist per page
  (shared id), so never nest this inside `app/1`.
  """
  def input_system_root(assigns) do
    ~H"""
    <div
      id="input-system"
      class={@class}
      phx-hook="InputSystem"
      data-input-bindings={Jason.encode!(input_bindings())}
      data-global-bindings={Jason.encode!(global_bindings())}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp input_bindings do
    resolved = MediaCentaur.Settings.Controls.get()
    catalog = MediaCentaur.Settings.Controls.Catalog.all()
    input_scope_ids = for b <- catalog, b.scope == :input_system, do: b.id

    %{
      keyboard:
        Enum.reduce(input_scope_ids, %{}, fn id, acc ->
          case resolved[id].key do
            nil -> acc
            key -> Map.put(acc, key, Atom.to_string(id))
          end
        end),
      gamepad:
        Enum.reduce(input_scope_ids, %{}, fn id, acc ->
          case resolved[id].button do
            nil -> acc
            btn -> Map.put(acc, Integer.to_string(btn), Atom.to_string(id))
          end
        end)
    }
  end

  defp global_bindings do
    resolved = MediaCentaur.Settings.Controls.get()
    catalog = MediaCentaur.Settings.Controls.Catalog.all()
    global_scope_ids = for b <- catalog, b.scope == :global, do: b.id

    Enum.reduce(global_scope_ids, %{}, fn id, acc ->
      case resolved[id].key do
        nil -> acc
        key -> Map.put(acc, Atom.to_string(id), key)
      end
    end)
  end

  # `paths` may be a list when one nav entry fronts several routes — the
  # Review entry covers both review dimensions (/review and /reconcile).
  # Collapsed-rail tooltips come from the SidebarTooltip hook reading each
  # link's data-tip — no tooltip classes here.
  defp sidebar_link_class(current_path, paths) do
    base = "sidebar-link"

    if current_path in List.wrap(paths) do
      base <> " sidebar-link-active"
    else
      base
    end
  end
end
