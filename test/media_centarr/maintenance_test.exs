defmodule MediaCentarr.MaintenanceTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Maintenance
  alias MediaCentarr.Review

  import MediaCentarr.TestFactory

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Review.list_pending_files()

      Maintenance.clear_database()

      assert [] = Review.list_pending_files()
    end
  end
end
