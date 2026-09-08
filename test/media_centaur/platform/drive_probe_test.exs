defmodule MediaCentaur.Platform.DriveProbeTest do
  use MediaCentaur.Case, async: false

  alias MediaCentaur.Platform.DriveProbe

  # async: false because we mutate Application env.

  defmodule FakeImpl do
    @behaviour MediaCentaur.Platform.DriveProbe

    @impl true
    def available_bytes(_path), do: {:ok, 42}

    @impl true
    def measure(_path), do: {:ok, %{device: "fake", mount_point: "/fake"}}
  end

  describe "facade dispatch" do
    test "delegates to the configured impl" do
      Application.put_env(:media_centaur, DriveProbe, FakeImpl)

      assert {:ok, 42} = DriveProbe.available_bytes("/anything")
      assert {:ok, %{device: "fake"}} = DriveProbe.measure("/anything")
    end

    test "defaults to GnuDf when no impl is configured" do
      Application.delete_env(:media_centaur, DriveProbe)

      # /tmp is a real path on Linux CI runners; the default impl is
      # GnuDf which shells out to `df` for real.
      assert {:ok, avail} = DriveProbe.available_bytes("/tmp")
      assert is_integer(avail) and avail > 0
    end
  end
end
