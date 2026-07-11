defmodule MediaCentaurWeb.GuideLive do
  @moduledoc """
  The in-app guide at `/guide` and `/guide/:slug`. A sidebar of parts →
  chapters, a reading pane rendering the current chapter's markdown, and an
  on-this-page outline. Entry point: Settings → System (not the main nav).
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Guide
  alias MediaCentaurWeb.GuideMarkdown

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, parts: Guide.parts(), page_title: "Guide")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    slug = params["slug"] || default_slug()

    case Guide.fetch_chapter(slug) do
      {:ok, chapter} ->
        {:noreply,
         assign(socket,
           chapter: chapter,
           body: GuideMarkdown.to_heex(chapter.body),
           outline: GuideMarkdown.outline(chapter.body)
         )}

      :error ->
        {:noreply, push_navigate(socket, to: ~p"/guide")}
    end
  end

  defp default_slug do
    case Guide.chapters() do
      [first | _] -> first.slug
      [] -> ""
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/guide"
      acquisition_ready={assigns[:acquisition_ready] || false}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
      review_pending={assigns[:review_pending] || 0}
      mapping_pending={assigns[:mapping_pending] || 0}
    >
      <div class="flex gap-8 max-w-[74rem]" data-page-behavior="guide" data-nav-default-zone="guide">
        <nav
          data-nav-zone="guide_chapters"
          class="w-48 shrink-0 sticky top-6 self-start space-y-4 px-1.5 thin-scrollbar overflow-y-auto"
          style="max-height: calc(100vh - 3rem)"
        >
          <div :for={{part, chapters} <- @parts}>
            <div class="px-3 mb-1 text-xs font-medium uppercase tracking-wider text-base-content/45">
              {part}
            </div>
            <.link
              :for={ch <- chapters}
              patch={~p"/guide/#{ch.slug}"}
              data-nav-item
              tabindex="0"
              class={[
                "block py-1.5 px-3 rounded-lg text-sm leading-snug text-base-content/70 transition-[opacity,background-color] duration-150 hover:bg-base-content/6",
                ch.slug == @chapter.slug && "text-primary bg-primary/10 font-medium"
              ]}
            >
              {ch.nav_label}
            </.link>
          </div>
        </nav>

        <article class="min-w-0 flex-1 max-w-[44rem]">
          <div class="glass-surface rounded-xl px-8 py-7">
            <div class="mb-2 text-xs font-medium uppercase tracking-wider text-primary/70">
              {@chapter.part}
            </div>
            <h1 class="text-2xl font-bold text-base-content mb-5">{@chapter.title}</h1>
            {@body}
          </div>
        </article>

        <aside
          :if={@outline != []}
          data-nav-zone="guide_outline"
          class="w-48 shrink-0 sticky top-6 self-start hidden xl:block"
        >
          <div class="mb-2 text-xs font-medium uppercase tracking-wider text-base-content/45">
            On this page
          </div>
          <a
            :for={{level, text, anchor} <- @outline}
            href={"#" <> anchor}
            data-nav-item
            tabindex="0"
            class={[
              "block text-sm py-1 text-base-content/55 hover:text-base-content transition-colors",
              level == 3 && "pl-3"
            ]}
          >
            {text}
          </a>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
