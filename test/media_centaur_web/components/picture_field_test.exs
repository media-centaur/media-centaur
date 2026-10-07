defmodule MediaCentaurWeb.Components.PictureFieldTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.PictureField

  describe "change/2 — what the consumed entries and a pending Remove mean" do
    test "a master wins over a pending Remove; nothing chosen is Remove or keep" do
      assert PictureField.change([{:new, "bytes"}], true) == {:ok, {:new, "bytes"}}
      assert PictureField.change([{:new, "bytes"}], false) == {:ok, {:new, "bytes"}}
      assert PictureField.change([], true) == {:ok, :none}
      assert PictureField.change([], false) == {:ok, :keep}
    end

    test "a file libvips could not open, or one over the cap, is refused whatever Remove says" do
      assert PictureField.change([:bad_image], true) == {:error, :bad_image}
      assert PictureField.change([:too_large], false) == {:error, :too_large}
    end
  end
end
