defmodule MediaCentaur.ContextMap.SchemasTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Schema
  alias MediaCentaur.ContextMap.Schemas

  test "TitleIntent: context, table, enum values, no virtual or timestamp fields" do
    intent = Schemas.fetch!(MediaCentaur.Discovery.TitleIntent)

    assert %Schema{context: MediaCentaur.Discovery, table: "title_intents"} = intent

    assert %{name: :rung, type: "Ecto.Enum", values: [:ignored, :list, :follow, :grab]} =
             field(intent, :rung)

    assert %{name: :activity_id, type: "Ecto.UUID", values: nil} = field(intent, :activity_id)
    refute field(intent, :title)
    refute field(intent, :inserted_at)
    refute field(intent, :id)
  end

  test "WatchHistory.Event carries belongs_to associations with their targets" do
    event = Schemas.fetch!(MediaCentaur.WatchHistory.Event)
    movie = Enum.find(event.associations, &(&1.target == MediaCentaur.Library.Movie))
    assert %{kind: :belongs_to, field: :movie_id} = movie
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
end
