defmodule MediaCentaur.Credo.Checks.PubSubTransport do
  use Credo.Check,
    id: "MC0025",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      `MediaCentaur.Topics` owns the PubSub transport. Nothing else in
      `lib/` calls `Phoenix.PubSub.broadcast/3`, `subscribe/2` or
      `unsubscribe/2` directly, because doing so means naming the PubSub
      server by hand — plumbing no caller has an opinion about, which was
      copied into 73 files before ADR-060.

          # preferred
          alias MediaCentaur.Topics

          Topics.publish(Topics.review_updates(), {:file_added, id})
          Topics.subscribe(Topics.review_updates())

          # NOT preferred — names the server, bypasses the seam
          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            Topics.review_updates(),
            {:file_added, id}
          )

      This is the transport layer only. It is not the whole story for a
      topic that has an owning context:

        * Prefer the context's `Events.broadcast/1` over `Topics.publish/2`
          when the topic has one — that is where the typed payload and its
          `@enforce_keys` guarantee live (ADR-060). MC0012, MC0013 and
          MC0026 enforce that for the topics that have chokepoints.
        * Prefer the context's `subscribe/0` facade over
          `Topics.subscribe/1` in LiveViews (MC0003).

      Exempt: `lib/media_centaur/topics.ex`, which *is* the seam, and all
      test files, which drive PubSub directly to assert on it.
      `MediaCentaur.Application`'s `{Phoenix.PubSub, name: …}` child spec
      is not a call site and is not matched.
      """
    ]

  @forbidden [:broadcast, :subscribe, :unsubscribe]

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
    String.contains?(filename, "lib/media_centaur/topics.ex") or
      String.starts_with?(filename, "test/") or
      String.contains?(filename, "/test/")
  end

  defp traverse(
         {{:., _, [{:__aliases__, _, [:Phoenix, :PubSub]}, fun]}, meta, _args} = ast,
         issues,
         issue_meta
       )
       when fun in @forbidden do
    {ast, [issue_for(issue_meta, "Phoenix.PubSub.#{fun}", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "`#{trigger}` bypasses the `MediaCentaur.Topics` transport seam. Use " <>
          "`Topics.publish/2`, `Topics.subscribe/1` or `Topics.unsubscribe/1` — or better, " <>
          "the owning context's `Events.broadcast/1` / `subscribe/0` facade (ADR-060).",
      trigger: trigger,
      line_no: line_no || 0
    )
  end
end
