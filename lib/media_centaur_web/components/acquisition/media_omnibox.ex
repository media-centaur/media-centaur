defmodule MediaCentaurWeb.Components.Acquisition.MediaOmnibox do
  @moduledoc """
  The Incoming page's hero search — one search surface, two modes
  (UIDR-014).

  **Media mode** (default) asks "What do you want to watch?": typing
  searches TMDB and the results render flat below the hero (the
  `MediaResults` section — page content, no overlay); picking a title
  starts a download plan. **Release mode** is the naked
  release-name search — the same box flips to the brace-expansion
  query form (monospace input, Enter to search, syntax hint, expansion
  preview) whose results render below the hero in the existing search
  zone. The flip toggle lives inside the card so the demoted naked
  search stays one click away, never buried.

  Pure rendering; events bubble to the parent LiveView. Release-mode
  event names match the legacy search zone's contract
  (`query_change` / `submit_search`) so the session machinery is
  untouched.
  """

  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  alias Phoenix.LiveView.JS
  alias MediaCentaurWeb.IncomingLive.SearchSession
  alias MediaCentaurWeb.IncomingLive.Logic

  attr :mode, :atom, required: true, values: [:media, :release]
  attr :query, :string, default: "", doc: "Media-mode query (release mode reads the session)."

  attr :session, SearchSession,
    default: nil,
    doc: "Release-mode session — required when `mode == :release`."

  attr :any_loading?, :boolean, default: false, doc: "Release-mode: any group still searching."

  attr :hero, :boolean,
    default: false,
    doc:
      "Incoming-page front-door treatment: centered column, larger input, and a mode-hint line below (the active mode emphasized). Same events either way."

  attr :release_mode_available, :boolean,
    default: true,
    doc:
      "Whether release search exists at all (an indexer is configured). When false the hero hint drops the release-mode flip and reads as tracking — the forecast-only page must not offer a grab flow."

  def media_omnibox(assigns) do
    ~H"""
    <%!-- Deliberately glass, not scrim — the search card stays a light
          floating surface above the page's scrim-toned cards (user call:
          the scrim version read too heavy here). Hero mode drops the card
          chrome entirely: the input floats on the page as the front door. --%>
    <section
      data-nav-zone="omnibox"
      class={[
        @hero && "mx-auto w-full max-w-2xl space-y-3",
        !@hero && "glass-surface rounded-xl p-4 space-y-3"
      ]}
    >
      <.media_form :if={@mode == :media} query={@query} hero={@hero} />
      <.release_form
        :if={@mode == :release}
        session={@session}
        any_loading?={@any_loading?}
        hero={@hero}
      />

      <.hero_mode_hint
        :if={@hero}
        mode={@mode}
        session={@session}
        release_mode_available={@release_mode_available}
      />

      <div :if={!@hero} class="flex items-baseline justify-between gap-3 text-xs">
        <span :if={@mode == :media} class="text-base-content/55">
          Type a movie or show — Media Centaur plans the downloads
        </span>
        <span :if={@mode == :release} class="flex flex-wrap items-center gap-x-3 text-base-content/55">
          <span>Syntax:</span>
          <code class="font-mono px-1.5 py-0.5 rounded bg-base-content/10 text-base-content/60">
            {"{a,b,c}"}
          </code>
          <code class="font-mono px-1.5 py-0.5 rounded bg-base-content/10 text-base-content/60">
            {"{00-09}"}
          </code>
          <span class={Logic.expansion_color(@session.expansion_preview)}>
            {Logic.expansion_text(@session.expansion_preview)}
          </span>
        </span>

        <button
          type="button"
          class="flex items-center gap-1 text-base-content/55 hover:text-base-content/80 transition-colors flex-shrink-0"
          phx-click="omnibox_mode"
          phx-value-mode={if @mode == :media, do: "release", else: "media"}
          data-nav-item
          tabindex="0"
        >
          <.icon
            name={if @mode == :media, do: "hero-command-line-mini", else: "hero-sparkles-mini"}
            class="size-3.5"
          />
          {if @mode == :media, do: "Release search", else: "Media search"}
        </button>
      </div>
    </section>
    """
  end

  attr :query, :string, required: true
  attr :hero, :boolean, required: true

  defp media_form(assigns) do
    ~H"""
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
          class={[
            "input input-bordered w-full pl-12 pr-12 text-base",
            (@hero && "h-[52px] rounded-xl") || "h-12"
          ]}
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
    """
  end

  attr :session, SearchSession, required: true
  attr :any_loading?, :boolean, required: true
  attr :hero, :boolean, required: true

  defp release_form(assigns) do
    ~H"""
    <%!-- No submit button, mirroring the media form — Enter is the only
          submit path (HTML implicit submission, single-field form). A
          disabled submit button once silently swallowed Enter here;
          buttonless makes that bug class unrepresentable. submit_search
          guards empty/invalid queries server-side. --%>
    <form
      id="release-omnibox-form"
      phx-change="query_change"
      phx-submit="submit_search"
      autocomplete="off"
    >
      <div class="relative">
        <.icon
          name="hero-command-line-mini"
          class="size-5 text-base-content/50 absolute left-4 top-1/2 -translate-y-1/2 z-10 pointer-events-none"
        />
        <input
          id="omnibox-release-input"
          type="text"
          name="query"
          value={@session.query}
          class={[
            "input input-bordered w-full pl-12 pr-12 font-mono text-sm",
            (@hero && "h-[52px] rounded-xl") || "h-12"
          ]}
          placeholder="Title S01E{01-10}"
          phx-debounce="200"
          phx-hook="MouseAutofocus"
          data-nav-item
          tabindex="0"
        />
        <%!-- The spinner yields the far-right slot to the X whenever a
              query is present (the X exists exactly then). --%>
        <span
          :if={@any_loading?}
          class={[
            "loading loading-spinner loading-sm absolute top-1/2 -translate-y-1/2 text-base-content/40",
            (@session.query != "" && "right-12") || "right-4"
          ]}
        ></span>
        <button
          :if={@session.query != ""}
          id="omnibox-release-clear"
          type="button"
          class="absolute right-3 top-1/2 -translate-y-1/2 z-10 cursor-pointer text-base-content/55 transition-colors hover:text-base-content/80"
          phx-click={
            JS.dispatch("omnibox:clear-input", to: "#omnibox-release-input")
            |> JS.push("clear_search")
          }
          aria-label="Clear search"
          data-nav-item
          tabindex="0"
        >
          <.icon name="hero-x-mark-mini" class="size-5" />
        </button>
      </div>
    </form>
    """
  end

  attr :mode, :atom, required: true
  attr :session, SearchSession, default: nil
  attr :release_mode_available, :boolean, required: true

  # The hero footer: release-mode syntax help (same vocabulary as the
  # card footer) above the mode hint with the active mode emphasized.
  # The inactive mode name is the flip control — same `omnibox_mode`
  # event as the card's corner toggle. Without an indexer there is no
  # release mode and no plan flow — the hint says what a pick does.
  defp hero_mode_hint(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-2 text-xs">
      <span
        :if={@mode == :release && @session}
        class="flex flex-wrap items-center justify-center gap-x-3 text-base-content/55"
      >
        <span>Syntax:</span>
        <code class="font-mono px-1.5 py-0.5 rounded bg-base-content/10 text-base-content/60">
          {"{a,b,c}"}
        </code>
        <code class="font-mono px-1.5 py-0.5 rounded bg-base-content/10 text-base-content/60">
          {"{00-09}"}
        </code>
        <span class={Logic.expansion_color(@session.expansion_preview)}>
          {Logic.expansion_text(@session.expansion_preview)}
        </span>
      </span>

      <p :if={@release_mode_available} class="text-center text-sm text-base-content/55">
        <.mode_hint_name active={@mode == :media} mode="media" label="Search titles" /> to add or plan
        <span class="mx-1.5 opacity-60">·</span>
        <.mode_hint_name active={@mode == :release} mode="release" label="search releases" /> directly
      </p>
      <p :if={!@release_mode_available} class="text-center text-sm text-base-content/55">
        <span class="font-medium text-base-content/70">Search titles</span> to track their releases
      </p>
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :mode, :string, required: true
  attr :label, :string, required: true

  defp mode_hint_name(assigns) do
    ~H"""
    <span :if={@active} class="font-medium text-base-content/70">{@label}</span>
    <button
      :if={!@active}
      type="button"
      class="cursor-pointer font-medium text-base-content/55 underline decoration-base-content/20 underline-offset-2 transition-colors hover:text-base-content/70"
      phx-click="omnibox_mode"
      phx-value-mode={@mode}
      data-nav-item
      tabindex="0"
    >
      {@label}
    </button>
    """
  end
end
