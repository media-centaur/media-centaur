defmodule MediaCentaurWeb.Components.Acquisition.MediaOmnibox do
  @moduledoc """
  Discovery's search box (UIDR-014, amended 2026-11-01 and 2026-11-02):
  "What do you want to watch?" over the hero's artwork, the placeholder
  alone. Typing searches TMDB (`Live.MediaSearch`, the host trait) and
  the results answer flat below as `MediaResults` — page content, no
  overlay; picking a row opens the title detail, where a title is listed
  or downloaded. The in-input X is the one dismissal.

  Pure rendering; `omnibox_change` and `omnibox_clear` bubble to the
  host. The section is the `omnibox` nav zone, so the Discovery
  behaviour's CLEAR (`discovery_behavior.js`) finds the input by its id.
  Release search is the Downloads page's own field (`DownloadsLive.Search`).
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS

  attr :query, :string, default: "", doc: "The typed query; `\"\"` at rest."

  def media_omnibox(assigns) do
    ~H"""
    <%!-- The input floats on the page as its front door: no card chrome, a
          centred column (on a media-center-wide screen a left-hugging
          column strands the right half of the display). --%>
    <section data-nav-zone="omnibox" class="mx-auto w-full max-w-2xl">
      <form
        id="media-omnibox-form"
        phx-change="omnibox_change"
        phx-submit="omnibox_change"
        autocomplete="off"
      >
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="size-5 text-base-content/50 absolute left-4 top-1/2 -translate-y-1/2 z-10 pointer-events-none"
          />
          <input
            id="omnibox-media-input"
            type="text"
            name="query"
            value={@query}
            class="input w-full pl-12 pr-12 text-base h-[52px] rounded-xl"
            placeholder="What do you want to watch?"
            phx-debounce="500"
            phx-hook="MouseAutofocus"
            data-nav-item
            tabindex="0"
          />
          <%!-- The input is cleared client-side too (the app.js
                omnibox:clear-input listener): LiveView never overwrites a
                focused input's value, so the server-side query reset alone
                would leave stale text in the box. --%>
          <button
            :if={@query != ""}
            id="omnibox-media-clear"
            type="button"
            class="absolute right-3 top-1/2 -translate-y-1/2 z-10 cursor-pointer text-base-content/55 transition-colors hover:text-base-content/80"
            phx-click={
              JS.dispatch("omnibox:clear-input", to: "#omnibox-media-input")
              |> JS.push("omnibox_clear")
            }
            aria-label="Clear search"
            data-nav-item
            tabindex="0"
          >
            <.icon name="hero-x-mark-mini" class="size-5" />
          </button>
        </div>
      </form>
    </section>
    """
  end
end
