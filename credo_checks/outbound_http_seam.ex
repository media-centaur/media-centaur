defmodule MediaCentaur.Credo.Checks.OutboundHttpSeam do
  use Credo.Check,
    id: "MC0029",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      `MediaCentaur.HttpClient.new/2` is the one seam every outbound
      HTTP request passes through. It tags the request with its
      upstream, instruments it for the Status page, attaches the
      response cache, and routes it to a `Req.Test` stub under test.
      A client built anywhere else is invisible to all four.

      Nothing in `lib/` outside `lib/media_centaur/http_client.ex`
      calls `Req.new/1`, and no call to `Req.get/2`, `Req.post/2`,
      `Req.request/2`, `Req.run/2` (or their `!` and other-verb
      siblings) takes a URL as its first argument — a URL-first call
      builds an anonymous client on the spot.

          # preferred
          client = MediaCentaur.HttpClient.new(__MODULE__, upstream: :github, base_url: @base_url)
          Req.get(client, url: "/repos/…/releases/latest")

          # NOT preferred — bypasses the seam
          Req.new(base_url: @base_url)
          Req.get("https://api.github.com/…")
          Req.get("\#{@base}/path", redirect: false)

      A URL passed in a variable (`Req.get(url, opts)`) cannot be told
      from a client statically and is not flagged; the reviewer's rule
      is the same.

      Exempt: `lib/media_centaur/http_client.ex`, which *is* the seam,
      and all test files, which build stub clients directly.
      """
    ]

  @seam "lib/media_centaur/http_client.ex"
  @verbs [
    :get,
    :get!,
    :post,
    :post!,
    :put,
    :put!,
    :patch,
    :patch!,
    :delete,
    :delete!,
    :head,
    :head!,
    :request,
    :request!,
    :run,
    :run!
  ]

  if !File.exists?(Path.expand(@seam, Path.join(__DIR__, ".."))) do
    raise CompileError,
      description:
        "MC0029 (OutboundHttpSeam) exempts #{@seam}, which does not exist. " <>
          "If the module moved, update the exemption path; if it was deleted, retire the check."
  end

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if exempt?(filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp exempt?(filename) do
    String.ends_with?(filename, @seam) or
      String.starts_with?(filename, "test/") or
      String.contains?(filename, "/test/")
  end

  defp traverse({{:., _, [{:__aliases__, _, [:Req]}, :new]}, meta, _args} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, "Req.new", meta[:line]) | issues]}
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Req]}, verb]}, meta, [first | _]} = ast,
         issues,
         issue_meta
       )
       when verb in @verbs do
    if url_literal?(first) do
      {ast, [issue_for(issue_meta, "Req.#{verb}", meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp url_literal?(arg) when is_binary(arg), do: true
  defp url_literal?({:<<>>, _, _}), do: true
  defp url_literal?({:<>, _, _}), do: true
  defp url_literal?(_), do: false

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` builds an HTTP client outside `MediaCentaur.HttpClient.new/2`, so the " <>
          "request has no upstream, no instrumentation, no cache, and no test stub. Build the " <>
          "client through the seam and pass it as the first argument.",
      trigger: trigger,
      line_no: line_no || 0
    )
  end
end
