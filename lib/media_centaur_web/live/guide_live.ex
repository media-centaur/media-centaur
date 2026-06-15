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
    <div class="flex gap-8 max-w-6xl mx-auto p-6">
      <nav class="w-56 shrink-0 sticky top-6 self-start space-y-4">
        <div :for={{part, chapters} <- @parts}>
          <div class="text-xs uppercase tracking-wider text-base-content/50 mb-1">{part}</div>
          <.link
            :for={ch <- chapters}
            patch={~p"/guide/#{ch.slug}"}
            class={[
              "block px-2 py-1 rounded text-sm",
              (ch.slug == @chapter.slug && "bg-base-content/10 text-base-content") ||
                "text-base-content/70 hover:bg-base-content/5"
            ]}
          >
            {ch.title}
          </.link>
        </div>
      </nav>

      <article class="min-w-0 flex-1">
        <h1 class="text-2xl font-bold text-base-content mb-4">{@chapter.title}</h1>
        {@body}
      </article>

      <aside
        :if={@outline != []}
        class="w-48 shrink-0 sticky top-6 self-start hidden xl:block"
      >
        <div class="text-xs uppercase tracking-wider text-base-content/50 mb-1">On this page</div>
        <a
          :for={{level, text, anchor} <- @outline}
          href={"#" <> anchor}
          class={[
            "block text-sm text-base-content/60 hover:text-base-content py-0.5",
            level == 3 && "pl-3"
          ]}
        >
          {text}
        </a>
      </aside>
    </div>
    """
  end
end
