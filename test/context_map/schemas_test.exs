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

  test "fields and associations carry their declaration line and trimmed declaration" do
    intent = Schemas.from_module(MediaCentaur.Discovery.TitleIntent)
    rung = field(intent, :rung)
    lines = "lib/media_centaur/discovery/title_intent.ex" |> File.read!() |> String.split("\n")

    assert rung.declaration =~ "field :rung"
    assert rung.declaration == String.trim(rung.declaration)
    assert lines |> Enum.at(rung.line - 1) |> String.trim() == rung.declaration

    event = Schemas.from_module(MediaCentaur.WatchHistory.Event)
    movie = Enum.find(event.associations, &(&1.name == :movie))
    assert movie.declaration =~ "belongs_to :movie"
    assert movie.line > 1
  end

  test "a belongs_to foreign key field takes its association's declaration" do
    event = Schemas.from_module(MediaCentaur.WatchHistory.Event)
    movie = Enum.find(event.associations, &(&1.name == :movie))
    assert %{line: line, declaration: declaration} = field(event, :movie_id)
    assert {line, declaration} == {movie.line, movie.declaration}
  end

  describe "declarations/2" do
    @nested """
    defmodule Sample.Parent do
      defmodule Child do
        embedded_schema do
          field :name, :string
        end
      end

      schema "parents" do
        field :name, :string
        belongs_to :owner, Sample.Owner
      end
    end
    """

    test "a declaration is found in the module's own body, not in a nested module" do
      assert %{name: {9, "field :name, :string"}, owner: {10, "belongs_to :owner, Sample.Owner"}} =
               Schemas.declarations(Sample.Parent, @nested)

      assert Schemas.declarations(Sample.Parent.Child, @nested) == %{name: {4, "field :name, :string"}}
    end

    test "an inline embed's own fields are not collected into the parent" do
      code = """
      defmodule Sample.Parent do
        schema "parents" do
          field :name, :string

          embeds_one :settings, Settings do
            field :theme, :string
          end
        end
      end
      """

      assert Schemas.declarations(Sample.Parent, code) == %{
               name: {3, "field :name, :string"},
               settings: {5, "embeds_one :settings, Settings do"}
             }
    end

    test "a module absent from the code has no declarations" do
      assert Schemas.declarations(Sample.Absent, @nested) == %{}
    end
  end

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
