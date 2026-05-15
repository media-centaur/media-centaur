defmodule MediaCentarr.Library.PersonTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Library.Person

  test "casts a cast member from TMDB-shaped map" do
    attrs = %{
      "name" => "Sample Actor",
      "character" => "Hero",
      "order" => 0,
      "profile_path" => "/abc.jpg",
      "tmdb_person_id" => 7
    }

    assert {:ok,
            %Person{
              name: "Sample Actor",
              character: "Hero",
              order: 0,
              profile_path: "/abc.jpg",
              tmdb_person_id: 7
            }} = Ecto.Changeset.apply_action(Person.cast_member_changeset(attrs), :insert)
  end

  test "casts a crew member with job/department" do
    attrs = %{
      "name" => "Sample Director",
      "job" => "Director",
      "department" => "Directing",
      "tmdb_person_id" => 9
    }

    assert {:ok,
            %Person{name: "Sample Director", job: "Director", department: "Directing", tmdb_person_id: 9}} =
             Ecto.Changeset.apply_action(Person.crew_member_changeset(attrs), :insert)
  end

  test "requires :name on cast members" do
    assert {:error, changeset} =
             Ecto.Changeset.apply_action(Person.cast_member_changeset(%{"character" => "Hero"}), :insert)

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "requires :name on crew members" do
    assert {:error, changeset} =
             Ecto.Changeset.apply_action(Person.crew_member_changeset(%{"job" => "Director"}), :insert)

    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
