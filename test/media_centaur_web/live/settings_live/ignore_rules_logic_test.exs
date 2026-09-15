defmodule MediaCentaurWeb.SettingsLive.IgnoreRulesLogicTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.SettingsLive.IgnoreRulesLogic, as: Logic

  defp context(overrides \\ %{}) do
    Map.merge(
      %{
        existing: [],
        linked_paths: [],
        media_dirs: ["/media"],
        exists?: true,
        readable?: true
      },
      overrides
    )
  end

  describe "validate_path_rule/2 — shape" do
    test "accepts an absolute path inside a media directory" do
      assert {:ok, "/media/Captures"} = Logic.validate_path_rule("/media/Captures", context())
    end

    test "trims surrounding whitespace" do
      assert {:ok, "/media/Captures"} = Logic.validate_path_rule("  /media/Captures  ", context())
    end

    test "rejects an empty input without an error message" do
      assert {:error, :empty} = Logic.validate_path_rule("   ", context())
      assert Logic.error_message(:empty, :path) == nil
    end

    test "rejects a relative path" do
      assert {:error, :relative} = Logic.validate_path_rule("Captures", context())
    end

    test "rejects a duplicate" do
      assert {:error, :duplicate} =
               Logic.validate_path_rule("/media/Captures", context(%{existing: ["/media/Captures"]}))
    end

    test "rejects a path that is not a directory" do
      assert {:error, :not_a_directory} =
               Logic.validate_path_rule("/media/Captures", context(%{exists?: false}))
    end

    test "rejects a path the app cannot read" do
      assert {:error, :not_readable} =
               Logic.validate_path_rule("/media/Captures", context(%{readable?: false}))
    end

    test "reports shape problems before reachability" do
      # A half-typed path should say what's wrong with the path, not
      # report a directory that doesn't exist yet.
      assert {:error, :relative} =
               Logic.validate_path_rule("Captu", context(%{exists?: false}))
    end
  end

  describe "validate_path_rule/2 — inside a media directory" do
    test "rejects a path outside every media directory" do
      assert {:error, :outside_media_dirs} =
               Logic.validate_path_rule("/etc/cron.d", context())
    end

    test "accepts a media directory itself" do
      assert {:ok, "/media"} = Logic.validate_path_rule("/media", context())
    end

    test "does not treat a sibling with a shared prefix as inside" do
      assert {:error, :outside_media_dirs} =
               Logic.validate_path_rule("/media-other/Captures", context())
    end

    test "accepts any path when no media directory is configured yet" do
      assert {:ok, "/anywhere"} = Logic.validate_path_rule("/anywhere", context(%{media_dirs: []}))
    end
  end

  describe "validate_path_rule/2 — the imported-content invariant" do
    test "rejects a rule covering an imported file, and counts them" do
      linked = [
        "/media/Captures/a.mkv",
        "/media/Captures/nested/b.mkv",
        "/media/Movies/c.mkv"
      ]

      assert {:error, {:has_imported_files, 2}} =
               Logic.validate_path_rule("/media/Captures", context(%{linked_paths: linked}))
    end

    test "accepts a rule that covers no imported file" do
      assert {:ok, "/media/Captures"} =
               Logic.validate_path_rule(
                 "/media/Captures",
                 context(%{linked_paths: ["/media/Movies/c.mkv"]})
               )
    end

    test "names the count and the remedy" do
      assert Logic.error_message({:has_imported_files, 1}, :path) =~ "1 file"
      assert Logic.error_message({:has_imported_files, 12}, :path) =~ "12 files"
      assert Logic.error_message({:has_imported_files, 12}, :path) =~ "Remove those titles first"
    end
  end

  describe "validate_name_rule/2" do
    test "accepts a name no imported file sits under" do
      assert {:ok, "Captures"} = Logic.validate_name_rule("Captures", context())
    end

    test "trims surrounding whitespace" do
      assert {:ok, "Captures"} = Logic.validate_name_rule(" Captures ", context())
    end

    test "rejects an empty input without an error message" do
      assert {:error, :empty} = Logic.validate_name_rule("  ", context())
      assert Logic.error_message(:empty, :name) == nil
    end

    test "rejects a duplicate case-insensitively" do
      # Name rules match case-insensitively, so "extras" and "Extras"
      # are the same rule and holding both would be misleading.
      assert {:error, :duplicate} =
               Logic.validate_name_rule("Extras", context(%{existing: ["extras"]}))
    end

    test "rejects a name whose folders hold imported files, wherever they appear" do
      linked = [
        "/media/Show/Extras/a.mkv",
        "/media/Film/extras/b.mkv",
        "/media/Movies/c.mkv"
      ]

      assert {:error, {:has_imported_files, 2}} =
               Logic.validate_name_rule("Extras", context(%{linked_paths: linked}))
    end

    test "a file's own name is not a folder name" do
      assert {:ok, "Extras"} =
               Logic.validate_name_rule("Extras", context(%{linked_paths: ["/media/Movies/Extras"]}))
    end

    test "names the count and the remedy" do
      assert Logic.error_message({:has_imported_files, 3}, :name) =~ "3 files"
      assert Logic.error_message({:has_imported_files, 3}, :name) =~ "Remove those titles first"
    end
  end

  describe "error_message/2" do
    test "returns nil when there is no rejection" do
      assert Logic.error_message(nil, :path) == nil
    end

    test "covers every rejection a validator can return" do
      for rejection <- [
            :relative,
            :duplicate,
            :not_a_directory,
            :not_readable,
            :outside_media_dirs,
            {:has_imported_files, 2}
          ] do
        assert is_binary(Logic.error_message(rejection, :path))
        assert is_binary(Logic.error_message(rejection, :name))
      end
    end
  end
end
