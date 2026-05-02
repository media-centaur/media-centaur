defmodule MediaCentarr.Credo.Checks.EntityModalContract do
  use Credo.Check,
    id: "MC0011",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      A LiveView that `use`s one of the auto-wiring traits below must not
      call the trait's underlying context `subscribe/0` itself. Each trait
      registers an `on_mount` callback that subscribes for the host
      automatically; a second subscribe in the host means every PubSub
      message is delivered twice.

          Trait                                         Forbidden subscribes
          MediaCentarrWeb.Live.EntityModal              Library, Playback
          MediaCentarrWeb.Live.SpoilerFreeAware         Settings

      The historical bug this prevents (the EntityModal case): a host that
      mounted the modal but forgot to wire one of the four PubSub messages
      silently let `:selected_entry` go stale after playback ended.
      Centralising the subscription + handler in the trait's `on_mount`
      callback made that failure mode impossible — but only as long as no
      host re-subscribes.

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

      A host that needs the trait's underlying context for additional
      reasons does NOT need to subscribe twice — the on_mount subscription
      delivers every message on the topic, so the host's own
      `handle_info/2` clauses for other variants flow through the same
      single subscription.
      """
    ]

  # Mapping of trait module → context modules whose `subscribe/0` the
  # trait owns. Add new entries as new auto-wiring traits are introduced.
  @trait_subscribes %{
    [:MediaCentarrWeb, :Live, :EntityModal] => [:Library, :Playback],
    [:MediaCentarrWeb, :Live, :SpoilerFreeAware] => [:Settings]
  }

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if liveview_path?(filename) do
      forbidden = forbidden_subscribes_for(source_file)

      if forbidden == [] do
        []
      else
        issue_meta = IssueMeta.for(source_file, params)
        Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, forbidden))
      end
    else
      []
    end
  end

  defp liveview_path?(filename) do
    String.contains?(filename, "lib/media_centarr_web/live/")
  end

  # Returns the deduplicated list of forbidden subscribe modules for this
  # file, based on which traits it `use`s.
  defp forbidden_subscribes_for(source_file) do
    Enum.uniq(Credo.Code.prewalk(source_file, fn ast, acc -> {ast, collect_forbidden(ast, acc)} end, []))
  end

  defp collect_forbidden({:use, _, [{:__aliases__, _, alias_path} | _]}, acc) do
    case Map.get(@trait_subscribes, alias_path) do
      nil -> acc
      forbidden -> forbidden ++ acc
    end
  end

  defp collect_forbidden(_ast, acc), do: acc

  # Looks for `Foo.subscribe(...)` where `Foo` is in the forbidden list.
  defp traverse(
         {{:., meta, [{:__aliases__, _, [module]}, :subscribe]}, _, _args} = ast,
         issues,
         issue_meta,
         forbidden
       ) do
    if module in forbidden do
      {ast, [issue_for(issue_meta, "#{module}.subscribe", meta[:line]) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _forbidden), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Hosts that `use` an auto-wiring LiveView trait must not call " <>
          "the trait's underlying `subscribe/0` themselves — the trait's " <>
          "on_mount callback already subscribes. Duplicate subscribes deliver " <>
          "each PubSub message twice. See the check explanation for the trait/context map.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
