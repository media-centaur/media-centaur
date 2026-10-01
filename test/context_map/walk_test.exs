defmodule MediaCentaur.ContextMap.WalkTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ContextMap.Sources
  alias MediaCentaur.ContextMap.Walk

  @code """
  defmodule Sample do
    import Ecto.Query

    def marker(:ignored), do: "Ignored"
    def marker(%{rung: rung}), do: rung
    def read(intent), do: intent.rung
    def write(changeset), do: Ecto.Changeset.put_change(changeset, :note, "x")
    def attrs, do: %{activity_id: 1, source: :friend}
    def query, do: from(i in Intent, where: i.rung != :ignored)
    def assign_it(socket) do
      %{rung: rung} = socket.assigns
      rung
    end
    def template(assigns) do
      ~H\"\"\"
      <p :if={@form == :ignored}>{@detail.rung}</p>
      \"\"\"
    end
  end
  """

  setup do
    %{mentions: Walk.mentions(Sources.parse("lib/media_centaur/sample.ex", @code))}
  end

  test "value literal in a def head is a pattern mention with its line", %{mentions: mentions} do
    assert %{kind: :value, atom: :ignored, line: 4, pattern?: true, template?: false} =
             find(mentions, :value, :ignored, 4)
  end

  test "map key in a def head is a pattern key; the same key in an expression is not", %{
    mentions: mentions
  } do
    assert %{pattern?: true} = find(mentions, :key, :rung, 5)
    assert %{pattern?: false} = find(mentions, :key, :activity_id, 8)
    assert %{pattern?: true} = find(mentions, :key, :rung, 11)
  end

  test "dot access and query field access are dot mentions", %{mentions: mentions} do
    assert find(mentions, :dot, :rung, 6)
    assert find(mentions, :dot, :rung, 9)
  end

  test "a value in an expression is not a pattern", %{mentions: mentions} do
    assert %{pattern?: false} = find(mentions, :value, :friend, 8)
    assert %{pattern?: false} = find(mentions, :value, :ignored, 9)
  end

  test "template strings yield template mentions on their own lines", %{mentions: mentions} do
    assert %{template?: true} = find(mentions, :value, :ignored, 16)
    assert %{template?: true} = find(mentions, :dot, :rung, 16)
  end

  test "keys are not also reported as values", %{mentions: mentions} do
    refute find(mentions, :value, :rung, 5)
  end

  defp find(mentions, kind, atom, line),
    do: Enum.find(mentions, &(&1.kind == kind and &1.atom == atom and &1.line == line))
end
