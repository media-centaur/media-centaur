defmodule MediaCentaurWeb.GuideMarkdown do
  @moduledoc """
  Renders guide chapter markdown to HEEx via Earmark's AST.

  We walk the AST ourselves (rather than emitting Earmark's HTML string) so we
  control the markup: heading anchors for deep-linking and the on-this-page
  outline, GitHub-style alert blockquotes (`> [!NOTE]`) as calm callouts, and
  internal cross-links as in-app live navigation while external links open in a
  new tab. Reading typography lives in the `.guide-prose` CSS block (a
  coordinated multi-element system), so the elements here carry semantic tags
  rather than per-element utility classes.

  This is a web-layer presentation concern; the `MediaCentaur.Guide` context
  stays data-only and hands us the raw markdown body.
  """
  use Phoenix.Component

  import MediaCentaurWeb.CoreComponents, only: [icon: 1]

  @doc "Render a markdown string to a HEEx rendered struct."
  def to_heex(markdown) when is_binary(markdown) do
    {:ok, ast, _messages} = Earmark.Parser.as_ast(markdown, gfm: true)
    assigns = %{nodes: ast}

    ~H"""
    <div class="guide-prose">
      <.render_node :for={n <- @nodes} node={n} />
    </div>
    """
  end

  attr :markdown, :string, required: true

  @doc "Preview/story wrapper: render a markdown string as styled guide prose."
  def prose(assigns) do
    ~H"{to_heex(@markdown)}"
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
    <.dynamic_tag tag_name={@tag} id={@anchor}>
      <.render_node :for={c <- @children} node={c} />
    </.dynamic_tag>
    """
  end

  defp render_node(%{node: {"blockquote", _a, children, _m}} = assigns) do
    case callout_kind(children) do
      {kind, rest} ->
        assigns = assign(assigns, kind: kind, icon: callout_icon(kind), rest: rest)

        ~H"""
        <aside class="guide-callout" data-callout={@kind}>
          <.icon name={@icon} class="guide-callout-icon size-4" />
          <div class="guide-callout-body">
            <.render_node :for={c <- @rest} node={c} />
          </div>
        </aside>
        """

      :plain ->
        assigns = assign(assigns, children: children)

        ~H"""
        <blockquote>
          <.render_node :for={c <- @children} node={c} />
        </blockquote>
        """
    end
  end

  defp render_node(%{node: {"a", attrs, children, _m}} = assigns) do
    href = find_attr(attrs, "href")
    assigns = assign(assigns, href: href, children: children, internal: internal?(href))

    ~H"""
    <.link :if={@internal} navigate={@href}>
      <.render_node :for={c <- @children} node={c} />
    </.link>
    <a :if={!@internal} href={@href} target="_blank" rel="noreferrer">
      <.render_node :for={c <- @children} node={c} />
    </a>
    """
  end

  # Generic passthrough for p, ul, ol, li, strong, em, code, pre, table, thead,
  # tbody, tr, th, td, hr, etc. — all styled by `.guide-prose` in CSS.
  defp render_node(%{node: {tag, _a, children, _m}} = assigns) do
    assigns = assign(assigns, tag: tag, children: children)

    ~H"""
    <.dynamic_tag tag_name={@tag}>
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

  defp callout_icon("warning"), do: "hero-exclamation-triangle-mini"
  defp callout_icon("important"), do: "hero-exclamation-circle-mini"
  defp callout_icon("tip"), do: "hero-light-bulb-mini"
  defp callout_icon(_), do: "hero-information-circle-mini"

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
end
