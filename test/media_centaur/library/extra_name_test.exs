defmodule MediaCentaur.Library.ExtraNameTest do
  @moduledoc """
  Writer-level invariant for `Extra.name`: re-deriving a name must never persist
  a blank value (deriver-model campaign, Phase 1). The only update path for an
  extra's name goes through `Library.Extras.rename/2`.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Library

  setup do
    movie = create_movie(%{name: "Sample Movie"})

    extra =
      create_extra(%{movie_id: movie.id, name: "Original", content_url: "/media/test/Extras/Clip.mkv"})

    %{extra: extra}
  end

  test "updates the name with a valid value", %{extra: extra} do
    assert {:ok, updated} = Library.Extras.rename(extra, "Behind the Scenes")
    assert updated.name == "Behind the Scenes"
  end

  test "trims surrounding whitespace", %{extra: extra} do
    assert {:ok, updated} = Library.Extras.rename(extra, "  Deleted Scene  ")
    assert updated.name == "Deleted Scene"
  end

  test "rejects an empty name", %{extra: extra} do
    assert {:error, changeset} = Library.Extras.rename(extra, "")
    refute changeset.valid?
    assert reload_name(extra) == "Original"
  end

  test "rejects a whitespace-only name", %{extra: extra} do
    assert {:error, changeset} = Library.Extras.rename(extra, "   ")
    refute changeset.valid?
    assert reload_name(extra) == "Original"
  end

  test "rejects a nil name", %{extra: extra} do
    assert {:error, changeset} = Library.Extras.rename(extra, nil)
    refute changeset.valid?
    assert reload_name(extra) == "Original"
  end

  defp reload_name(extra) do
    Repo.get!(MediaCentaur.Library.Extra, extra.id).name
  end
end
