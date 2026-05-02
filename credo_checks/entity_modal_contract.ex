defmodule MediaCentarr.Credo.Checks.EntityModalContract do
  use Credo.Check,
    id: "MC0011",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      A LiveView that `use`s `MediaCentarrWeb.Live.EntityModal` must not
      call `Library.subscribe/0` or `Playback.subscribe/0` itself. The
      modal's `on_mount` callback subscribes to both topics automatically;
      a second subscribe in the host means every PubSub message is
      delivered twice.

      The historical bug this prevents: a host that mounted the modal but
      forgot to wire one of the four PubSub messages
      (`:entity_progress_updated`, `:extra_progress_updated`,
      `:entities_changed`, `:playback_state_changed`) silently let the
      modal's `:selected_entry` go stale after playback ended. Centralising
      the subscriptions inside `EntityModal.on_mount/4` made that failure
      mode impossible — but only as long as no host re-subscribes here.

          # preferred
          use MediaCentarrWeb.Live.EntityModal

          def mount(_, _, socket) do
            if connected?(socket), do: ReleaseTracking.subscribe()
            # Library.subscribe() / Playback.subscribe() are auto-wired.
            {:ok, socket}
          end

          # NOT preferred — duplicate subscribe, messages delivered twice
          use MediaCentarrWeb.Live.EntityModal

          def mount(_, _, socket) do
            if connected?(socket) do
              Library.subscribe()
              Playback.subscribe()
            end
            {:ok, socket}
          end
      """
    ]

  @forbidden [:Library, :Playback]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if liveview_path?(filename) and uses_entity_modal?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp liveview_path?(filename) do
    String.contains?(filename, "lib/media_centarr_web/live/")
  end

  defp uses_entity_modal?(source_file) do
    Credo.Code.prewalk(
      source_file,
      fn ast, acc -> {ast, acc or use_entity_modal_node?(ast)} end,
      false
    )
  end

  # use MediaCentarrWeb.Live.EntityModal
  defp use_entity_modal_node?(
         {:use, _, [{:__aliases__, _, [:MediaCentarrWeb, :Live, :EntityModal]} | _]}
       ), do: true

  defp use_entity_modal_node?(_), do: false

  # Library.subscribe() / Playback.subscribe()
  defp traverse(
         {{:., meta, [{:__aliases__, _, [module]}, :subscribe]}, _, _args} = ast,
         issues,
         issue_meta
       )
       when module in @forbidden do
    {ast, [issue_for(issue_meta, "#{module}.subscribe", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Hosts that `use MediaCentarrWeb.Live.EntityModal` must not call " <>
          "`Library.subscribe/0` or `Playback.subscribe/0` — the modal's on_mount " <>
          "callback already subscribes for them. Duplicate subscribes deliver each " <>
          "PubSub message twice.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
