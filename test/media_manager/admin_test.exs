defmodule MediaManager.AdminTest do
  use MediaManager.DataCase, async: false

  alias MediaManager.Admin
  alias MediaManager.Review.PendingFile

  import MediaManager.TestFactory

  describe "clear_database/0" do
    test "destroys pending review files" do
      create_pending_file()
      create_pending_file()

      assert [_, _] = Ash.read!(PendingFile, action: :read)

      Admin.clear_database()

      assert [] = Ash.read!(PendingFile, action: :read)
    end
  end
end
