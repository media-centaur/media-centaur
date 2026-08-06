defmodule MediaCentaur.Credo.Checks.ReviewUpdatesContract do
  use Credo.Check,
    id: "MC0026",
    base_priority: :high,
    category: :design,
    explanations: [
      check: """
      Every message published on the `review:updates` topic must go
      through `MediaCentaur.Review.Events.broadcast/1`. Publishing the
      tagged tuple directly bypasses the typed struct payloads and their
      `@enforce_keys` guarantee.

          # preferred
          alias MediaCentaur.Review.Events
          alias MediaCentaur.Review.Events.GroupApproved

          Events.broadcast(%GroupApproved{group_key: key, count: approved})

          # NOT preferred — nothing checks the arity or the order
          Topics.publish(Topics.review_updates(), {:group_approved, key, approved})

      `review:updates` is ADR-060's worked example, and two of its four
      messages used to be positional 3-tuples — the shape where a
      publisher can swap two same-typed arguments and no subscriber can
      tell. That is what the structs are for.

      The check exempts `lib/media_centaur/review/events.ex` itself (the
      canonical chokepoint) and all test files.
      """
    ]

  @forbidden_tags [:file_added, :file_reviewed, :group_approved, :group_error]
  @chokepoint "lib/media_centaur/review/events.ex"

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
          "`MediaCentaur.Review.Events` chokepoint. Use `Events.broadcast/1` with the " <>
          "matching struct so @enforce_keys catches missing fields at compile time.",
      trigger: "{:#{tag}, …}",
      line_no: line_no
    )
  end
end
