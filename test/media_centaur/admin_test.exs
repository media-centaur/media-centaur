defmodule MediaCentaur.AdminTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Admin
  alias MediaCentaur.Review

  import MediaCentaur.TestFactory

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Review.list_pending_files!()

      Admin.clear_database()

      assert [] = Review.list_pending_files!()
    end
  end
end
