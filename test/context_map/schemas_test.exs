defmodule MediaCentaur.ContextMap.SchemasTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Schemas

  test "TitleIntent: context, table, enum values, no virtual or timestamp fields" do
    intent = Schemas.from_module(MediaCentaur.Discovery.TitleIntent)

    assert %Schema{
             context: MediaCentaur.Discovery,
             table: "title_intents",
             file: "lib/media_centaur/discovery/title_intent.ex"
           } = intent

    assert %{name: :rung, type: "Ecto.Enum", values: [:ignored, :list, :follow, :grab]} =
             field(intent, :rung)

    assert %{name: :activity_id, type: "Ecto.UUID", values: nil} = field(intent, :activity_id)
    refute field(intent, :title)
    refute field(intent, :inserted_at)
    refute field(intent, :id)
  end

  test "WatchHistory.Event carries belongs_to associations with their targets" do
    event = Schemas.from_module(MediaCentaur.WatchHistory.Event)
    movie = Enum.find(event.associations, &(&1.target == MediaCentaur.Library.Movie))
    assert %{kind: :belongs_to, foreign_key: :movie_id, name: :movie} = movie
  end

  test "every schema has an owning context" do
    assert Enum.all?(Schemas.all(), &(&1.context != nil))
  end

  test "value_owners maps an enum value to the fields that declare it" do
    owners = Schemas.value_owners(Schemas.all())
    assert {MediaCentaur.Discovery.TitleIntent, :rung} in owners[:ignored]
    assert length(owners[:movie]) > 1
  end

  defp field(schema, name), do: Enum.find(schema.fields, &(&1.name == name))

  test "a schema source outside the project root raises naming the module" do
    assert_raise ArgumentError, ~r/MediaCentaur.Discovery.TitleIntent.*outside/, fn ->
      Schemas.source_file(MediaCentaur.Discovery.TitleIntent, "/nonexistent-root")
    end
  end

  test "a schema source inside the project root is relative to it" do
    assert Schemas.source_file(MediaCentaur.Discovery.TitleIntent, File.cwd!()) ==
             "lib/media_centaur/discovery/title_intent.ex"
  end
end
