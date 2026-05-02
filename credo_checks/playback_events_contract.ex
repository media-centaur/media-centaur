defmodule MediaCentarr.Credo.Checks.PlaybackEventsContract do
  use Credo.Check,
    id: "MC0012",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every message broadcast on the `playback:events` topic must go
      through `MediaCentarr.Playback.Events.broadcast/1`. Direct calls to
      `Phoenix.PubSub.broadcast/3` with one of the topic-tagged tuples
      (`:entity_progress_updated`, `:extra_progress_updated`,
      `:playback_state_changed`, `:playback_failed`) bypass the typed
      struct payloads — exactly the silent-payload-mismatch class of bug
      the structs were introduced to prevent.

          # preferred
          alias MediaCentarr.Playback.Events
          alias MediaCentarr.Playback.Events.PlaybackStateChanged

          Events.broadcast(%PlaybackStateChanged{
            entity_id: id, state: :playing, now_playing: np, started_at: ts
          })

          # NOT preferred — bypasses the @enforce_keys guarantee
          Phoenix.PubSub.broadcast(
            MediaCentarr.PubSub,
            MediaCentarr.Topics.playback_events(),
            {:playback_state_changed, id, :playing, np, ts}
          )

      The check exempts `lib/media_centarr/playback/events.ex` itself
      (the canonical chokepoint), all test files (which need to construct
      payloads for assertions, but should still prefer the struct), and
      docstrings/moduledocs.
      """
    ]

  @forbidden_tags [
    :entity_progress_updated,
    :extra_progress_updated,
    :playback_state_changed,
    :playback_failed
  ]

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    cond do
      String.contains?(filename, "lib/media_centarr/playback/events.ex") ->
        []

      String.starts_with?(filename, "test/") or String.contains?(filename, "/test/") ->
        []

      true ->
        issue_meta = IssueMeta.for(source_file, params)
        Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  # Phoenix.PubSub.broadcast(_, _, {:tag, ...})
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Phoenix, :PubSub]}, :broadcast]}, _,
          [_pubsub, _topic, {tag, _, _} = payload]} = ast,
         issues,
         issue_meta
       )
       when tag in @forbidden_tags do
    line = elem(payload, 1)[:line]
    {ast, [issue_for(issue_meta, "Phoenix.PubSub.broadcast({:#{tag}, …})", line) | issues]}
  end

  # Match the literal 2-tuple form `{:tag, payload}` (the typical shape)
  defp traverse(
         {{:., _, [{:__aliases__, _, [:Phoenix, :PubSub]}, :broadcast]}, meta,
          [_pubsub, _topic, {:{}, _, [tag | _]}]} = ast,
         issues,
         issue_meta
       )
       when tag in @forbidden_tags do
    {ast, [issue_for(issue_meta, "Phoenix.PubSub.broadcast({:#{tag}, …})", meta[:line]) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Direct `Phoenix.PubSub.broadcast` of a playback:events payload bypasses the " <>
          "typed `MediaCentarr.Playback.Events` chokepoint. Use `Events.broadcast/1` with " <>
          "the matching struct so @enforce_keys catches missing fields at compile time.",
      trigger: trigger,
      line_no: line_no || 0
    )
  end
end
