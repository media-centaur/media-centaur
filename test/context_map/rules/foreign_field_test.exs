defmodule MediaCentaur.ContextMap.Rules.ForeignFieldTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Finding
  alias MediaCentaur.ContextMap.Rules.ForeignField
  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Sources

  @intent %Schema{
    module: MediaCentaur.Discovery.TitleIntent,
    file: "lib/media_centaur/discovery/title_intent.ex",
    context: MediaCentaur.Discovery,
    table: "title_intents",
    fields: [
      %{name: :rung, type: "Ecto.Enum", values: [:ignored, :list]},
      %{name: :activity_id, type: "Ecto.UUID", values: nil},
      %{name: :note, type: ":string", values: nil}
    ],
    associations: []
  }
  @activity %Schema{
    module: MediaCentaur.Activities.Activity,
    file: "lib/media_centaur/activities/activity.ex",
    context: MediaCentaur.Activities,
    table: "activities",
    fields: [%{name: :note, type: ":string", values: nil}],
    associations: []
  }
  @schemas [@intent, @activity]

  @schema_file {"lib/media_centaur/discovery/title_intent.ex",
                "defmodule MediaCentaur.Discovery.TitleIntent do\n  def changeset(i, attrs), do: cast(i, attrs, [:rung, :activity_id, :note])\nend\n"}
  @discovery {"lib/media_centaur/discovery.ex",
              "defmodule MediaCentaur.Discovery do\n  def rungs, do: Repo.all(from(i in TitleIntent, select: {i.tmdb_id, i.rung}))\n  def note(%TitleIntent{note: note}), do: note\nend\n"}
  @activities {"lib/media_centaur/activities.ex",
               "defmodule MediaCentaur.Activities do\n  alias MediaCentaur.Discovery.TitleIntent\n  def link(title, id), do: Discovery.put_rung(title, :list, %{activity_id: id})\n  def own(%Activity{note: note}), do: note\nend\n"}

  defp parse(files), do: Enum.map(files, fn {path, code} -> Sources.parse(path, code) end)
  defp run(files), do: ForeignField.findings(@schemas, ForeignField.usage(@schemas, parse(files)))

  test "a field the owner never reads, written from another context, yields both findings" do
    findings =
      [@schema_file, @discovery, @activities] |> run() |> Enum.filter(&(&1.field == :activity_id))

    assert Enum.find(
             findings,
             &match?(
               %Finding{rule: "R1", owner: MediaCentaur.Discovery, detail: %{kind: :owner_never_reads}},
               &1
             )
           )

    assert %Finding{
             detail: %{kind: :foreign_write},
             consumer_context: MediaCentaur.Activities,
             consumer: MediaCentaur.Activities,
             line: 3
           } = Enum.find(findings, &match?(%{detail: %{kind: :foreign_write}}, &1))
  end

  test "a field the owner reads and nobody else writes is clean" do
    assert [] = [@schema_file, @discovery, @activities] |> run() |> Enum.filter(&(&1.field == :rung))
  end

  test "a non-distinctive field name counts only files that reference the owning schema" do
    # :note is on both schemas; Activities reads its own Activity.note without
    # referencing TitleIntent — not attributed to TitleIntent.
    findings =
      [@schema_file, @discovery, @activities]
      |> run()
      |> Enum.filter(&(&1.schema == MediaCentaur.Activities.Activity))

    assert [%Finding{field: :note, detail: %{kind: :owner_never_reads}}] = findings
  end

  test "the usage table reports reads and writes per context" do
    usage = ForeignField.usage(@schemas, parse([@schema_file, @discovery, @activities]))

    assert %{reads: %{MediaCentaur.Discovery => 1}, writes: writes} =
             usage[{MediaCentaur.Discovery.TitleIntent, :rung}]

    assert writes == %{}

    assert %{reads: reads, writes: %{MediaCentaur.Activities => 1}} =
             usage[{MediaCentaur.Discovery.TitleIntent, :activity_id}]

    assert reads == %{}
  end

  test "a call named like cast is not a write; a Changeset.cast permitted list is" do
    code =
      "defmodule MediaCentaur.Activities do\n  def a, do: broadcast(:activity_id)\n  def b(c, attrs), do: Changeset.cast(c, attrs, [:activity_id])\nend\n"

    usage = ForeignField.usage(@schemas, parse([{"lib/media_centaur/activities.ex", code}]))

    assert [
             {MediaCentaur.Activities, MediaCentaur.Activities, "lib/media_centaur/activities.ex", 3,
              :write}
           ] =
             usage[{MediaCentaur.Discovery.TitleIntent, :activity_id}].sites
  end

  test "a keyword argument is not a write; a map literal argument is" do
    keyword =
      "defmodule MediaCentaur.Activities do\n  def link(title, id), do: Discovery.put_rung(title, :list, activity_id: id)\nend\n"

    map =
      "defmodule MediaCentaur.Activities do\n  def link(title, id), do: Discovery.put_rung(title, :list, %{activity_id: id})\nend\n"

    writes = fn code ->
      usage = ForeignField.usage(@schemas, parse([{"lib/media_centaur/activities.ex", code}]))
      usage[{MediaCentaur.Discovery.TitleIntent, :activity_id}].writes
    end

    assert writes.(keyword) == %{}
    assert writes.(map) == %{MediaCentaur.Activities => 1}
  end
end
