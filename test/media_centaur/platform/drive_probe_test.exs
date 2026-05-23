defmodule MediaCentaur.Platform.DriveProbeTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Platform.DriveProbe

  # async: false because we mutate Application env. The override is
  # rolled back in `on_exit` so the test is hermetic at the suite level
  # while still serialized within this file.

  defmodule FakeImpl do
    @behaviour MediaCentaur.Platform.DriveProbe

    @impl true
    def available_bytes(_path), do: {:ok, 42}

    @impl true
    def measure(_path), do: {:ok, %{device: "fake", mount_point: "/fake"}}
  end

  describe "facade dispatch" do
    test "delegates to the configured impl" do
      original = Application.get_env(:media_centaur, DriveProbe)
      Application.put_env(:media_centaur, DriveProbe, FakeImpl)

      on_exit(fn ->
        if original do
          Application.put_env(:media_centaur, DriveProbe, original)
        else
          Application.delete_env(:media_centaur, DriveProbe)
        end
      end)

      assert {:ok, 42} = DriveProbe.available_bytes("/anything")
      assert {:ok, %{device: "fake"}} = DriveProbe.measure("/anything")
    end

    test "defaults to GnuDf when no impl is configured" do
      original = Application.get_env(:media_centaur, DriveProbe)
      Application.delete_env(:media_centaur, DriveProbe)

      on_exit(fn ->
        if original, do: Application.put_env(:media_centaur, DriveProbe, original)
      end)

      # /tmp is a real path on Linux CI runners; the default impl is
      # GnuDf which shells out to `df` for real.
      assert {:ok, avail} = DriveProbe.available_bytes("/tmp")
      assert is_integer(avail) and avail > 0
    end
  end
end
