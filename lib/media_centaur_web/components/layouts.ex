defmodule MediaCentaurWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
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
  attr :full_width, :boolean, default: false, doc: "when true, removes max-w-7xl constraint"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div id="input-system" class="flex min-h-screen" phx-hook="InputSystem">
      <aside id="sidebar" class="sidebar glass-sidebar" data-nav-zone="sidebar">
        <nav class="flex flex-col gap-0.5">
          <.link
            navigate="/"
            class={sidebar_link_class(@current_path, "/")}
            data-tip="Library"
            data-nav-item
            data-nav-remember
            tabindex="0"
          >
            <.icon name="hero-book-open" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Library</span>
          </.link>
          <.link
            navigate="/status"
            class={sidebar_link_class(@current_path, "/status")}
            data-tip="Status"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-squares-2x2" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Status</span>
          </.link>
          <.link
            navigate="/review"
            class={sidebar_link_class(@current_path, "/review")}
            data-tip="Review"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-document-text" class="size-5 flex-shrink-0" />
            <span class="sidebar-label">Review</span>
          </.link>
          <.link
            navigate="/settings"
            class={sidebar_link_class(@current_path, "/settings")}
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

        <div
          class="sidebar-theme-nav"
          data-nav-item
          data-nav-focus-target
          data-nav-defer-activate
          data-nav-action="phx:cycle-theme"
          tabindex="0"
        >
          <div class="sidebar-theme-wrap" data-nav-focus-ring>
            <.theme_toggle />
          </div>

          <button
            class="sidebar-theme-cycle sidebar-link tooltip tooltip-right"
            phx-click={JS.dispatch("phx:cycle-theme")}
            data-tip="Theme"
            data-nav-focus-ring
          >
            <.icon
              name="hero-computer-desktop-micro"
              class="size-5 flex-shrink-0 theme-icon theme-icon-system"
            />
            <.icon name="hero-sun-micro" class="size-5 flex-shrink-0 theme-icon theme-icon-light" />
            <.icon name="hero-moon-micro" class="size-5 flex-shrink-0 theme-icon theme-icon-dark" />
          </button>
        </div>

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
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  defp sidebar_link_class(current_path, path) do
    base = "sidebar-link tooltip tooltip-right"

    if current_path == path do
      base <> " sidebar-link-active"
    else
      base
    end
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center w-full border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex items-center justify-center p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex items-center justify-center p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex items-center justify-center p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
