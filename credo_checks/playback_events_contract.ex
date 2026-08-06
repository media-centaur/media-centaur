defmodule MediaCentaur.Credo.Checks.PlaybackEventsContract do
  use Credo.Check,
    id: "MC0012",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every message broadcast on the `playback:events` topic must go
      through `MediaCentaur.Playback.Events.broadcast/1`. Direct calls to
      `Phoenix.PubSub.broadcast/3` with one of the topic-tagged tuples
      (`:entity_progress_updated`, `:extra_progress_updated`,
      `:playback_state_changed`, `:playback_failed`) bypass the typed
      struct payloads — exactly the silent-payload-mismatch class of bug
      the structs were introduced to prevent.

          # preferred
          alias MediaCentaur.Playback.Events
          alias MediaCentaur.Playback.Events.PlaybackStateChanged

          Events.broadcast(%PlaybackStateChanged{
            entity_id: id, state: :playing, now_playing: np, started_at: ts
          })

          # NOT preferred — bypasses the @enforce_keys guarantee
          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            MediaCentaur.Topics.playback_events(),
            {:playback_state_changed, id, :playing, np, ts}
          )

      The check exempts `lib/media_centaur/playback/events.ex` itself
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
  @chokepoint "lib/media_centaur/playback/events.ex"

  alias MediaCentaur.Credo.Checks.EventChokepoint

  @impl true
  def run(%SourceFile{filename: filename} = source_file, params) do
    if EventChokepoint.exempt?(filename, @chokepoint) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> EventChokepoint.publications(@forbidden_tags)
      |> Enum.map(fn {tag, line} -> issue_for(issue_meta, tag, line) end)
    end
  end

  defp issue_for(issue_meta, tag, line_no) do
    format_issue(
      issue_meta,
      message:
        "Publishing `{:#{tag}, …}` directly bypasses the typed " <>
          "`MediaCentaur.Playback.Events` chokepoint. Use `Events.broadcast/1` with the " <>
          "matching struct so @enforce_keys catches missing fields at compile time.",
      trigger: "{:#{tag}, …}",
      line_no: line_no
    )
  end
end
