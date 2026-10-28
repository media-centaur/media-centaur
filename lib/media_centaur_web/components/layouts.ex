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

  alias MediaCentaurWeb.Components.SidebarLink
  alias MediaCentaurWeb.Components.ViewingLayer

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

      <Layouts.app
        flash={@flash}
        badges={@badges}
        show_social={@show_social}
        show_apps={@show_apps}
        profile={@profile}
        profiles={@profiles}
        viewing_layer={assigns[:viewing_layer]}
      >
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_path, :string, default: nil, doc: "the current request path for nav highlighting"

  attr :badges, MediaCentaurWeb.ShellBadges.Counts,
    default: %MediaCentaurWeb.ShellBadges.Counts{},
    doc: """
    The sidebar's badge counts, seeded app-wide by `MediaCentaurWeb.ShellBadges`
    (default `live_session` on_mount) and live-refreshed via the `shell:badges`
    derived topic. See `ShellBadges.Counts` for the two idioms — follow-up
    pills and the condition dot (UIDR-030).
    """

  attr :show_social, :boolean,
    default: true,
    doc: """
    Whether the sidebar shows the Social entry — the `show_social`
    preference (`MediaCentaur.Settings.Preferences.SocialVisibility`, default on;
    switched under Settings → Social). Seeded app-wide by the
    `SettingAware` on_mount in the default `live_session`; only the nav
    entry is gated — `/social` stays reachable by URL.
    """

  attr :show_apps, :boolean,
    default: false,
    doc: """
    Whether the sidebar shows the Apps launcher entry — the `show_apps`
    preference (`MediaCentaur.Settings.Preferences.AppsVisibility`, default off).
    Seeded app-wide by the `SettingAware` on_mount in the default
    `live_session`; only the nav entry is gated — `/apps` stays reachable
    by URL.
    """

  attr :profile, MediaCentaur.Profiles.Profile,
    required: true,
    doc: "the session's active profile (`Live.ProfileAware`)"

  attr :profiles, :list,
    required: true,
    doc: "every profile; the switcher shows only with more than one"

  attr :full_width, :boolean, default: false, doc: "when true, removes max-w-7xl constraint"

  attr :viewing_layer, :map,
    default: nil,
    doc:
      "the viewing layer's state from `Live.ViewingAware` (`viewing`, `bar_shown?`, `menu_open?`) when this " <>
        "socket's player is a remote player with a viewing; nil on the host and between viewings"

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
    >
      <%!-- The one tooltip (hooks/tooltip.js): fixed, outside every clipping
            surface, moved beside whichever [data-tip] anchor is hovered or
            focused. The sidebar's links tip to the right of the rail; every
            other anchor tips beneath itself. --%>
      <div
        id="app-tooltip"
        class="app-tooltip"
        phx-hook="Tooltip"
        data-state="closed"
        aria-hidden="true"
      >
      </div>
      <%!-- The sidebar: a fixed 52px icon rail of `SidebarLink.sidebar_link`
            entries in two groups. Watch sits at the top; System is pinned
            to the bottom, the space between them its group marker. --%>
      <aside
        id="sidebar"
        class="sidebar glass-sidebar"
        data-nav-zone="sidebar"
        data-tip-placement="right"
      >
        <nav aria-label="Watch" class="flex flex-col gap-0.5">
          <SidebarLink.sidebar_link
            id="sidebar-home"
            navigate="/"
            label="Home"
            icon="hero-home"
            active={current?(@current_path, "/")}
            remember
          />
          <SidebarLink.sidebar_link
            id="sidebar-library"
            navigate="/library"
            label="Library"
            icon="hero-book-open"
            active={current?(@current_path, "/library")}
            remember
          />
          <SidebarLink.sidebar_link
            :if={@show_social}
            id="sidebar-social"
            navigate="/social"
            label="Social"
            icon="hero-users"
            active={current?(@current_path, ["/social", "/social/friends"])}
            remember
          />
          <%!-- One entry for the whole collection-growth story (UIDR-015) —
                unconditional: without acquisition the page degrades to an
                honest forecast instead of disappearing. --%>
          <SidebarLink.sidebar_link
            id="sidebar-incoming"
            navigate="/incoming"
            label="Incoming"
            icon="hero-inbox-arrow-down"
            active={current?(@current_path, "/incoming")}
            count={@badges.plans_awaiting_review}
            remember
          />
          <SidebarLink.sidebar_link
            :if={@show_apps}
            id="sidebar-apps"
            navigate="/apps"
            label="Apps"
            icon="hero-rocket-launch"
            active={current?(@current_path, "/apps")}
            remember
          />
        </nav>

        <nav
          id="sidebar-system"
          aria-label="System"
          class="sidebar-group-system flex flex-col gap-0.5"
        >
          <%!-- The profile switcher (UIDR-053 rule 3): a System entry like
                the others, a person icon in the profile's hue — no picture —
                linking to the picker, which opens inside this shell and
                lights this entry; present only when there is someone to
                switch to. Its name carries the active profile's name, since
                the icon alone cannot. Activates on focus like every
                sibling: landing on it during keyboard/gamepad navigation
                only visits the picker page, the same low-risk preview
                every other entry already gives — switching profiles still
                needs a second, explicit SELECT on a tile within it. --%>
          <SidebarLink.sidebar_link
            :if={length(@profiles) > 1}
            id="sidebar-profile"
            navigate={~p"/profiles"}
            label={profile_switch_label(@profile)}
            icon="hero-user-circle"
            active={current?(@current_path, "/profiles")}
            system
            hue={@profile.hue}
          />
          <SidebarLink.sidebar_link
            id="sidebar-status"
            navigate="/status"
            label="Status"
            icon="hero-squares-2x2"
            active={current?(@current_path, "/status")}
            system
            count={@badges.diagnostics_unseen}
            condition={@badges.status_errors > 0}
          />
          <SidebarLink.sidebar_link
            :if={@badges.review_pending + @badges.mapping_pending > 0}
            id="sidebar-review"
            navigate={if @badges.review_pending > 0, do: "/review", else: "/episode-mapping"}
            label="Review"
            icon="hero-document-text"
            active={current?(@current_path, ["/review", "/episode-mapping"])}
            system
            count={@badges.review_pending + @badges.mapping_pending}
          />
          <SidebarLink.sidebar_link
            id="sidebar-settings"
            navigate="/settings"
            label="Settings"
            icon="hero-cog-6-tooth"
            active={current?(@current_path, "/settings")}
            system
            remember
          />
        </nav>
      </aside>

      <main class="flex-1 min-w-0 px-6 py-6 flex flex-col">
        <div class={["flex-1 min-h-0 space-y-4", !@full_width && "max-w-7xl"]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      {render_slot(@overlays)}
      <ViewingLayer.viewing_layer
        :if={@viewing_layer}
        viewing={@viewing_layer.viewing}
        bar_shown?={@viewing_layer.bar_shown?}
        menu_open?={@viewing_layer.menu_open?}
      />
    </div>

    <.flash_group flash={@flash} />
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
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp input_bindings do
    resolved = MediaCentaur.Settings.Controls.get()
    ids = for b <- MediaCentaur.Settings.Controls.Catalog.all(), do: b.id

    %{
      keyboard:
        Enum.reduce(ids, %{}, fn id, acc ->
          case resolved[id].key do
            nil -> acc
            key -> Map.put(acc, key, Atom.to_string(id))
          end
        end),
      gamepad:
        Enum.reduce(ids, %{}, fn id, acc ->
          case resolved[id].button do
            nil -> acc
            btn -> Map.put(acc, Integer.to_string(btn), Atom.to_string(id))
          end
        end)
    }
  end

  # `paths` may be a list when one nav entry fronts several routes — the
  # Review entry covers both review dimensions (/review and /episode-mapping).
  defp current?(current_path, paths), do: current_path in List.wrap(paths)

  # The switcher's name and tip: who is active, and what the entry does.
  defp profile_switch_label(profile), do: "#{profile.name} · Switch profile"
end
