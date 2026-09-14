defmodule MediaCentaur.Credo.Checks.LiveSubscriptions do
  use Credo.Check,
    id: "MC0011",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      A LiveView, or a trait a LiveView mounts, subscribes to a context's
      topic through `MediaCentaurWeb.Live.Subscriptions.subscribe/2` — the
      one door — never by calling the context's `subscribe/0` (or
      `Topics.subscribe/1`) itself.

      The door subscribes a process to a topic once, whichever consumer
      declares it: a page declaring `MediaCentaur.Library` for its grid
      and the title detail host declaring it for the open modal share one
      subscription, so no message is delivered twice and no consumer
      depends on another having subscribed first. A direct call bypasses
      that ledger — the historical bug: a host that subscribed a topic a
      trait had already subscribed received every message twice.

          # preferred
          def mount(_, _, socket) do
            socket =
              socket
              |> Subscriptions.subscribe(MediaCentaur.WatchHistory)
              |> Subscriptions.subscribe({MediaCentaur.Acquisition, :subscribe_queue})

            {:ok, socket}
          end

          # NOT preferred — outside the ledger, and delivered twice when a
          # trait declares the same topic
          def mount(_, _, socket) do
            if connected?(socket), do: WatchHistory.subscribe()
            {:ok, socket}
          end

      A module under `live/` that *defines* a `subscribe/0` is a facade of
      its own topic (`IncomingLive.SearchSession`) and may subscribe
      through `Topics`; the door itself is the one caller of a context's
      `subscribe/0`.
      """
    ]

  @door [:Subscriptions]
  @door_file "lib/media_centaur_web/live/subscriptions.ex"

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if liveview_path?(filename) and not String.ends_with?(filename, @door_file) and
         not facade?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp liveview_path?(filename), do: String.contains?(filename, "lib/media_centaur_web/live/")

  # A module defining `subscribe/0` owns a topic; its own call to
  # `Topics.subscribe/1` is the facade, not a bypass.
  defp facade?(source_file) do
    Credo.Code.prewalk(source_file, fn
      {:def, _, [{:subscribe, _, args} | _]} = ast, _acc when args in [nil, []] -> {ast, true}
      ast, acc -> {ast, acc}
    end, false)
  end

  # `Foo.subscribe()` on any alias but the door, and `Topics.subscribe(topic)`.
  defp traverse({{:., meta, [{:__aliases__, _, alias_path}, :subscribe]}, _, args} = ast, issues, issue_meta)
       when alias_path != @door do
    case {List.last(alias_path), args} do
      {_module, []} -> {ast, [issue_for(issue_meta, Enum.join(alias_path, ".") <> ".subscribe", meta[:line]) | issues]}
      {:Topics, [_topic]} -> {ast, [issue_for(issue_meta, "Topics.subscribe", meta[:line]) | issues]}
      _other -> {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Subscribe through the one door — `Subscriptions.subscribe(socket, Context)` — " <>
          "not by calling the context's `subscribe/0` directly. The door subscribes a " <>
          "topic once per process, whichever consumer declares it.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
