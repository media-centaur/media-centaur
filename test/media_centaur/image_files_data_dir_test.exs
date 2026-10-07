defmodule MediaCentaur.ImageFilesDataDirTest do
  use MediaCentaur.Case, async: false

  import MediaCentaur.TmpDataDir

  alias MediaCentaur.ImageFiles

  describe "data-dir file primitives" do
    setup :setup_tmp_data_dir

    test "write_file creates the directory, remove_file tolerates absence, url_if_present answers only for a file on disk",
         %{data_dir: data_dir} do
      relative = "images/sample/one.webp"
      assert ImageFiles.url_if_present(relative, 7) == nil

      assert :ok = ImageFiles.write_file(relative, "bytes")
      assert File.read!(Path.join(data_dir, relative)) == "bytes"
      assert ImageFiles.url_if_present(relative, 7) == "/media-images/images/sample/one.webp?v=7"

      assert :ok = ImageFiles.remove_file(relative)
      assert :ok = ImageFiles.remove_file(relative)
      assert ImageFiles.url_if_present(relative, 7) == nil
    end
  end
end
