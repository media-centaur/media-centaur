defmodule MediaCentarr.Watcher.DirValidatorTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Watcher.DirValidator

  defp stub_fs(overrides \\ %{}) do
    defaults = %{
      exists?: fn _ -> true end,
      dir?: fn _ -> true end,
      readable?: fn _ -> true end,
      ls: fn _ -> {:ok, []} end,
      touch: fn _ -> :ok end,
      expand: &Path.expand/1,
      mount_for: fn _ -> {:ok, "/"} end,
      mounted?: fn _ -> true end
    }

    Map.merge(defaults, overrides)
  end

  defp candidate(dir, opts \\ []) do
    %{
      "id" => opts[:id],
      "dir" => dir,
      "images_dir" => opts[:images_dir],
      "name" => opts[:name]
    }
  end

  describe "dir field — existence/type/readability" do
    test "passes when path exists, is a dir, and is readable" do
      assert %{errors: [], warnings: _} =
               DirValidator.validate(candidate("/mnt/a"), [], stub_fs())
    end

    test "errors when path does not exist" do
      fs = stub_fs(%{exists?: fn _ -> false end})
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), [], fs)
      assert Enum.any?(errors, &match?({:dir, :not_found}, &1))
    end

    test "errors when path is not a directory" do
      fs = stub_fs(%{dir?: fn _ -> false end})
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), [], fs)
      assert Enum.any?(errors, &match?({:dir, :not_a_directory}, &1))
    end

    test "errors when path is not readable" do
      fs = stub_fs(%{readable?: fn _ -> false end})
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), [], fs)
      assert Enum.any?(errors, &match?({:dir, :not_readable}, &1))
    end
  end

  describe "dir field — duplicate/nested" do
    test "errors when dir duplicates an existing entry" do
      existing = [candidate("/mnt/a", id: "existing")]
      assert %{errors: errors} = DirValidator.validate(candidate("/mnt/a"), existing, stub_fs())
      assert Enum.any?(errors, &match?({:dir, :duplicate}, &1))
    end

    test "edit of self is not a duplicate" do
      existing = [candidate("/mnt/a", id: "me")]

      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/a", id: "me"), existing, stub_fs())

      refute Enum.any?(errors, &match?({:dir, :duplicate}, &1))
    end

    test "errors when dir is nested inside an existing entry" do
      existing = [candidate("/mnt/videos", id: "root")]

      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/videos/movies"), existing, stub_fs())

      assert Enum.any?(errors, &match?({:dir, :nested}, &1))
    end

    test "errors when dir contains an existing entry" do
      existing = [candidate("/mnt/videos/movies", id: "child")]

      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/videos"), existing, stub_fs())

      assert Enum.any?(errors, &match?({:dir, :contains_existing}, &1))
    end
  end

  describe "dir field — mount awareness" do
    test "warns when path is under an unmounted mount point" do
      fs = stub_fs(%{mounted?: fn _ -> false end, mount_for: fn _ -> {:ok, "/mnt/nas"} end})
      assert %{warnings: warnings} = DirValidator.validate(candidate("/mnt/nas/media"), [], fs)
      assert Enum.any?(warnings, &match?({:dir, :unmounted, _}, &1))
    end
  end

  describe "images_dir" do
    test "allows images_dir nested inside a watch dir (watcher auto-excludes it)" do
      existing = [candidate("/mnt/a", id: "existing")]
      fs = stub_fs()
      entry = candidate("/mnt/b", images_dir: "/mnt/a/cache")
      assert %{errors: errors} = DirValidator.validate(entry, existing, fs)

      refute Enum.any?(errors, fn
               {:images_dir, _} -> true
               _ -> false
             end)
    end

    test "errors when images_dir cannot be created and does not exist" do
      fs =
        stub_fs(%{
          exists?: fn
            "/mnt/a" -> true
            "/mnt/unwritable/images" -> false
            "/mnt/unwritable" -> true
            _ -> true
          end,
          touch: fn _ -> {:error, :eacces} end
        })

      entry = candidate("/mnt/a", images_dir: "/mnt/unwritable/images")
      assert %{errors: errors} = DirValidator.validate(entry, [], fs)
      assert Enum.any?(errors, &match?({:images_dir, :unwritable}, &1))
    end
  end

  describe "name" do
    test "errors when name duplicates another entry's name" do
      existing = [candidate("/mnt/a", id: "existing", name: "Movies")]
      entry = candidate("/mnt/b", name: "Movies")
      assert %{errors: errors} = DirValidator.validate(entry, existing, stub_fs())
      assert Enum.any?(errors, &match?({:name, :duplicate}, &1))
    end

    test "errors when name exceeds 60 characters" do
      long = String.duplicate("x", 61)

      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/a", name: long), [], stub_fs())

      assert Enum.any?(errors, &match?({:name, :too_long}, &1))
    end

    test "empty name is allowed" do
      assert %{errors: errors} =
               DirValidator.validate(candidate("/mnt/a", name: nil), [], stub_fs())

      refute Enum.any?(errors, &match?({:name, _}, &1))
    end
  end

  describe "preview" do
    test "returns preview counts based on ls" do
      fs =
        stub_fs(%{
          ls: fn _ ->
            {:ok, ["movie.mkv", "show.mp4", "notes.txt", "subdir"]}
          end,
          dir?: fn
            "/mnt/a" -> true
            "/mnt/a/subdir" -> true
            _ -> false
          end
        })

      assert %{preview: %{video_count: 2, subdir_count: 1}} =
               DirValidator.validate(candidate("/mnt/a"), [], fs)
    end
  end
end
