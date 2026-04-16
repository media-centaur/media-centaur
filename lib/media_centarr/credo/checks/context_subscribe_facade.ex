defmodule MediaCentarr.Credo.Checks.ContextSubscribeFacade do
  use Credo.Check,
    id: "MC0003",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      LiveViews must subscribe to PubSub topics through context facade
      functions (`Library.subscribe/0`, `Playback.subscribe/0`, etc.) rather
      than calling `Phoenix.PubSub.subscribe/2` directly. Topic knowledge
      stays in the context that owns it.

          # preferred (in lib/media_centarr_web/live/foo_live.ex)
          if connected?(socket) do
            Library.subscribe()
            Playback.subscribe()
          end

          # NOT preferred
          if connected?(socket) do
            Phoenix.PubSub.subscribe(MediaCentarr.PubSub, "library:updates")
          end

      Source: CLAUDE.md "Context facade subscribe pattern".
      """
    ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if liveview_path?(filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp liveview_path?(filename) do
    String.contains?(filename, "lib/media_centarr_web/live/")
  end

  # Phoenix.PubSub.subscribe(...)
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:Phoenix, :PubSub]}, :subscribe]}, _, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, "Phoenix.PubSub.subscribe", meta[:line]) | issues]}
  end

  # PubSub.subscribe(...) when aliased
  defp traverse(
         {{:., meta, [{:__aliases__, _, [:PubSub]}, :subscribe]}, _, _args} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, "PubSub.subscribe", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "LiveViews must subscribe via a context facade (e.g. `Library.subscribe()`), " <>
          "not by calling `Phoenix.PubSub.subscribe/2` directly. See CLAUDE.md.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
