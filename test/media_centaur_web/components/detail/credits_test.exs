defmodule MediaCentaurWeb.Components.Detail.CreditsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Library.Person
  alias MediaCentaurWeb.Components.Detail.Credits

  defp person(name, job), do: %Person{name: name, job: job}

  test "each role draws one line, directors first, in crew order within a role" do
    crew = [
      person("Writer A", "Screenplay"),
      person("Director A", "Director"),
      person("Composer A", "Original Music Composer"),
      person("Writer B", "Story"),
      person("Director B", "Director")
    ]

    assert [
             {:directed, "Directed by", [%{name: "Director A"}, %{name: "Director B"}]},
             {:written, "Written by", [%{name: "Writer A"}, %{name: "Writer B"}]}
           ] = Credits.lines(crew)
  end

  test "a series' creators are its line" do
    assert [{:created, "Created by", [%{name: "Creator A"}]}] =
             Credits.lines([person("Creator A", "Creator")])
  end

  test "a crew with none of the three roles draws nothing" do
    assert Credits.lines([person("Editor A", "Editor")]) == []
    assert Credits.lines([]) == []
  end
end
