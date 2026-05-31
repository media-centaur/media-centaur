defmodule MediaCentaur.Library.CollectionArtworkTest do
  use ExUnit.Case, async: true

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.CollectionArtwork

  defp image(role), do: build_image(%{role: role, content_url: "#{role}.jpg"})

  describe "effective_images/2" do
    test "leaves own art untouched when both display roles are present" do
      own = [image("poster"), image("backdrop")]
      fallback = [image("poster"), image("backdrop")]

      assert CollectionArtwork.effective_images(own, fallback) == own
    end

    test "borrows the missing role from the fallback list" do
      own = [image("poster")]
      borrowed_backdrop = image("backdrop")

      result = CollectionArtwork.effective_images(own, [borrowed_backdrop])

      assert result == own ++ [borrowed_backdrop]
    end

    test "borrows both poster and backdrop when the collection has none" do
      poster = image("poster")
      backdrop = image("backdrop")

      result = CollectionArtwork.effective_images([], [poster, backdrop])

      roles = Enum.map(result, & &1.role)
      assert Enum.sort(roles) == ["backdrop", "poster"]
    end

    test "borrows from the first matching fallback (preferred source wins)" do
      first = build_image(%{role: "backdrop", content_url: "first.jpg"})
      second = build_image(%{role: "backdrop", content_url: "second.jpg"})

      assert [borrowed] = CollectionArtwork.effective_images([], [first, second])
      assert borrowed.content_url == "first.jpg"
    end

    test "never borrows a logo even when one is offered and the collection lacks it" do
      result = CollectionArtwork.effective_images([], [image("logo")])

      assert result == []
    end

    test "own art is never overridden by a same-role fallback" do
      own_poster = build_image(%{role: "poster", content_url: "own.jpg"})
      other_poster = build_image(%{role: "poster", content_url: "other.jpg"})

      assert CollectionArtwork.effective_images([own_poster], [other_poster]) == [own_poster]
    end

    test "returns own images unchanged when fallback is not a list" do
      own = [image("poster")]

      assert CollectionArtwork.effective_images(own, %Ecto.Association.NotLoaded{}) == own
    end

    test "returns [] when own images is not a list" do
      assert CollectionArtwork.effective_images(%Ecto.Association.NotLoaded{}, []) == []
    end
  end
end
