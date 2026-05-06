defmodule MediaCentarrWeb.Live.SetupLive.BinaryDetectorTest do
  use ExUnit.Case, async: true

  alias MediaCentarrWeb.Live.SetupLive.BinaryDetector

  setup do
    tmp_root = Path.join(System.tmp_dir!(), "binary_detector_#{Ecto.UUID.generate()}")
    bin_a = Path.join(tmp_root, "bin_a")
    bin_b = Path.join(tmp_root, "bin_b")
    bin_c = Path.join(tmp_root, "bin_c")

    File.mkdir_p!(bin_a)
    File.mkdir_p!(bin_b)
    File.mkdir_p!(bin_c)

    on_exit(fn -> File.rm_rf!(tmp_root) end)

    %{tmp_root: tmp_root, bin_a: bin_a, bin_b: bin_b, bin_c: bin_c}
  end

  defp touch!(dir, name) do
    path = Path.join(dir, name)
    File.write!(path, "")
    path
  end

  # Unique fake binary name so System.find_executable/1 never returns
  # a real /usr/bin hit and contaminates the test result.
  defp fake_name, do: "fake-binary-#{Ecto.UUID.generate()}"

  describe "detect/2" do
    test "returns paths where the binary exists", %{bin_a: bin_a, bin_b: bin_b, bin_c: bin_c} do
      name = fake_name()
      path_a = touch!(bin_a, name)
      path_b = touch!(bin_b, name)
      # bin_c intentionally has no binary

      detected = BinaryDetector.detect(name, [bin_a, bin_b, bin_c])

      assert path_a in detected
      assert path_b in detected
      refute Path.join(bin_c, name) in detected
    end

    test "returns empty list when binary is nowhere", %{bin_a: bin_a, bin_b: bin_b} do
      assert BinaryDetector.detect(fake_name(), [bin_a, bin_b]) == []
    end

    test "deduplicates paths", %{bin_a: bin_a} do
      name = fake_name()
      path = touch!(bin_a, name)
      detected = BinaryDetector.detect(name, [bin_a, bin_a, bin_a])
      assert detected == [path]
    end

    test "only returns regular files, not directories", %{bin_a: bin_a} do
      name = fake_name()
      File.mkdir_p!(Path.join(bin_a, name))
      assert BinaryDetector.detect(name, [bin_a]) == []
    end

    test "expands ~ in paths" do
      # No crash, list result — "~/.local/bin" may or may not exist on
      # the test machine.
      assert is_list(BinaryDetector.detect(fake_name(), ["~/.local/bin"]))
    end
  end

  describe "detect/1 (with default common paths)" do
    test "returns a list (smoke — depends on what's on this machine)" do
      result = BinaryDetector.detect("ls")
      assert is_list(result)
      # "ls" is on every Linux system; if this fails, the function is broken.
      assert Enum.any?(result, &String.ends_with?(&1, "/ls"))
    end
  end
end
