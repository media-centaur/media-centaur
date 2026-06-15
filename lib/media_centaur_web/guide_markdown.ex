defmodule MediaCentaurWeb.GuideMarkdown do
  @moduledoc """
  Renders guide chapter markdown to HEEx via Earmark's AST.

  We walk the AST ourselves (rather than emitting Earmark's HTML string) so we
  control styling, add heading anchors for deep-linking and the on-this-page
  outline, turn GitHub-style alert blockquotes (`> [!NOTE]`) into styled
  callouts, and keep internal cross-links as in-app live navigation while
  opening external links in a new tab.

  This is a web-layer presentation concern; the `MediaCentaur.Guide` context
  stays data-only and hands us the raw markdown body.
  """
  use Phoenix.Component

  @doc "Render a markdown string to a HEEx rendered struct."
  def to_heex(markdown) when is_binary(markdown) do
    {:ok, ast, _messages} = Earmark.Parser.as_ast(markdown, gfm: true)
    assigns = %{nodes: ast}

    ~H"""
    <div class="guide-prose space-y-4 leading-relaxed text-base-content/85">
      <.render_node :for={n <- @nodes} node={n} />
    </div>
    """
  end

  @doc "Extract the on-this-page outline as `[{level, text, anchor}]` for h2/h3."
  def outline(markdown) when is_binary(markdown) do
    {:ok, ast, _messages} = Earmark.Parser.as_ast(markdown, gfm: true)

    for {tag, _attrs, children, _meta} <- ast, tag in ~w(h2 h3) do
      text = node_text(children)
      {tag |> String.trim_leading("h") |> String.to_integer(), text, slugify(text)}
    end
  end

  # --- node dispatch -------------------------------------------------------

  attr :node, :any,
    required: true,
    doc:
      "An Earmark AST node: a `{tag, attrs, children, meta}` tuple or a bare text binary. Heterogeneous tagged-union shape — `:any` is intentional."

  defp render_node(%{node: {tag, _a, children, _m}} = assigns) when tag in ~w(h1 h2 h3 h4) do
    assigns = assign(assigns, tag: tag, anchor: slugify(node_text(children)), children: children)

    ~H"""
    <.dynamic_tag tag_name={@tag} id={@anchor} class={heading_class(@tag)}>
      <.render_node :for={c <- @children} node={c} />
    </.dynamic_tag>
    """
  end

  defp render_node(%{node: {"blockquote", _a, children, _m}} = assigns) do
    case callout_kind(children) do
      {kind, rest} ->
        assigns = assign(assigns, kind: kind, rest: rest)

        ~H"""
        <aside data-callout={@kind} class={callout_class(@kind)}>
          <.render_node :for={c <- @rest} node={c} />
        </aside>
        """

      :plain ->
        assigns = assign(assigns, children: children)

        ~H"""
        <blockquote class="border-l-2 border-base-content/20 pl-4 italic">
          <.render_node :for={c <- @children} node={c} />
        </blockquote>
        """
    end
  end

  defp render_node(%{node: {"a", attrs, children, _m}} = assigns) do
    href = find_attr(attrs, "href")
    assigns = assign(assigns, href: href, children: children, internal: internal?(href))

    ~H"""
    <.link
      :if={@internal}
      navigate={@href}
      class="text-primary underline underline-offset-2 hover:opacity-80"
    >
      <.render_node :for={c <- @children} node={c} />
    </.link>
    <a
      :if={!@internal}
      href={@href}
      target="_blank"
      rel="noreferrer"
      class="text-primary underline underline-offset-2 hover:opacity-80"
    >
      <.render_node :for={c <- @children} node={c} />
    </a>
    """
  end

  defp render_node(%{node: {"code", _a, children, _m}} = assigns) do
    assigns = assign(assigns, children: children)

    ~H"""
    <code class="font-mono text-sm px-1 py-0.5 rounded bg-base-content/10">
      <.render_node :for={c <- @children} node={c} />
    </code>
    """
  end

  defp render_node(%{node: {"pre", _a, children, _m}} = assigns) do
    assigns = assign(assigns, children: children)

    ~H"""
    <pre class="font-mono text-sm p-3 rounded bg-base-300 overflow-x-auto"><.render_node :for={c <- @children} node={c} /></pre>
    """
  end

  # Generic passthrough for p, ul, ol, li, strong, em, table, thead, tbody,
  # tr, th, td, hr, etc.
  defp render_node(%{node: {tag, _a, children, _m}} = assigns) do
    assigns = assign(assigns, tag: tag, children: children)

    ~H"""
    <.dynamic_tag tag_name={@tag} class={generic_class(@tag)}>
      <.render_node :for={c <- @children} node={c} />
    </.dynamic_tag>
    """
  end

  defp render_node(%{node: text} = assigns) when is_binary(text) do
    assigns = assign(assigns, text: text)
    ~H"{@text}"
  end

  # --- helpers -------------------------------------------------------------

  defp find_attr(attrs, key), do: Enum.find_value(attrs, fn {k, v} -> if k == key, do: v end)

  defp internal?(href), do: is_binary(href) and String.starts_with?(href, "/")

  defp node_text(children) do
    children
    |> List.wrap()
    |> Enum.map_join("", fn
      t when is_binary(t) -> t
      {_tag, _a, kids, _m} -> node_text(kids)
    end)
  end

  @callout_re ~r/\A\s*\[!(NOTE|TIP|WARNING|IMPORTANT)\]\s*/i

  defp callout_kind(children) do
    case Regex.run(@callout_re, node_text(children)) do
      [_full, kind] -> {String.downcase(kind), strip_marker(children)}
      _ -> :plain
    end
  end

  # Drop the `[!KIND]` marker from the first text run of the first paragraph.
  defp strip_marker(children) do
    Enum.map(children, fn
      {"p", a, kids, m} -> {"p", a, drop_leading_marker(kids), m}
      other -> other
    end)
  end

  defp drop_leading_marker([first | rest]) when is_binary(first),
    do: [Regex.replace(~r/\A\s*\[![A-Za-z]+\]\s*/, first, "") | rest]

  defp drop_leading_marker(kids), do: kids

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  defp heading_class("h2"), do: "text-xl font-semibold text-base-content pt-4 scroll-mt-20"
  defp heading_class("h3"), do: "text-lg font-semibold text-base-content pt-2 scroll-mt-20"
  defp heading_class(_), do: "font-semibold text-base-content scroll-mt-20"

  defp callout_class("warning"), do: "rounded-md border border-warning/40 bg-warning/10 p-3 space-y-2"

  defp callout_class("tip"), do: "rounded-md border border-success/40 bg-success/10 p-3 space-y-2"
  defp callout_class(_), do: "rounded-md border border-info/40 bg-info/10 p-3 space-y-2"

  defp generic_class("ul"), do: "list-disc pl-5 space-y-1"
  defp generic_class("ol"), do: "list-decimal pl-5 space-y-1"
  defp generic_class("table"), do: "w-full text-sm border-collapse"
  defp generic_class("th"), do: "text-left font-semibold border-b border-base-content/20 p-2"
  defp generic_class("td"), do: "border-b border-base-content/10 p-2"
  defp generic_class("strong"), do: "font-semibold text-base-content"
  defp generic_class(_), do: nil
end
