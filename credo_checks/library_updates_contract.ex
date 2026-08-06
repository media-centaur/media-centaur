defmodule MediaCentaur.Credo.Checks.LibraryUpdatesContract do
  use Credo.Check,
    id: "MC0013",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every message broadcast on the `library:updates` topic must go
      through `MediaCentaur.Library.Events.broadcast/1`. Direct calls to
      `Phoenix.PubSub.broadcast/3` with one of the topic-tagged tuples
      (`:entities_changed`, …) bypass the typed struct payloads — exactly
      the silent-payload-mismatch class of bug the structs were
      introduced to prevent.

          # preferred
          alias MediaCentaur.Library.Events
          alias MediaCentaur.Library.Events.EntitiesChanged

          Events.broadcast(%EntitiesChanged{entity_ids: ids})

          # NOT preferred — bypasses the @enforce_keys guarantee
          Phoenix.PubSub.broadcast(
            MediaCentaur.PubSub,
            MediaCentaur.Topics.library_updates(),
            {:entities_changed, ids}
          )

      The check exempts `lib/media_centaur/library/events.ex` itself
      (the canonical chokepoint) and all test files (which need to
      construct payloads for assertions, but should still prefer the
      struct).
      """
    ]

  @forbidden_tags [:entities_changed]
  @chokepoint "lib/media_centaur/library/events.ex"

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
          "`MediaCentaur.Library.Events` chokepoint. Use `Events.broadcast/1` with the " <>
          "matching struct so @enforce_keys catches missing fields at compile time.",
      trigger: "{:#{tag}, …}",
      line_no: line_no
    )
  end
end
