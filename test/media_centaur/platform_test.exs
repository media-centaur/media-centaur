defmodule MediaCentaur.PlatformTest do
  use ExUnit.Case, async: false

  # async: false because pick_impl/2 reads Application env; tests
  # mutate it and roll back via on_exit. on_exit is safe here — it's
  # an in-memory ETS-like op, not a DB write.

  alias MediaCentaur.Platform

  defmodule FakeFacade do
  end

  defmodule FakeLinux do
  end

  defmodule FakeDarwin do
  end

  describe "pick_impl/3 — Application env override wins" do
    setup do
      original = Application.get_env(:media_centaur, FakeFacade)
      Application.put_env(:media_centaur, FakeFacade, FakeDarwin)

      on_exit(fn ->
        if original do
          Application.put_env(:media_centaur, FakeFacade, original)
        else
          Application.delete_env(:media_centaur, FakeFacade)
        end
      end)

      :ok
    end

    test "explicit override beats the OS-based default" do
      # Even claiming to be on Linux, the override (FakeDarwin) wins.
      assert Platform.pick_impl(
               FakeFacade,
               [linux: FakeLinux, darwin: FakeDarwin],
               os_type: {:unix, :linux}
             ) == FakeDarwin
    end
  end

  describe "pick_impl/3 — OS-based default when no override" do
    setup do
      original = Application.get_env(:media_centaur, FakeFacade)
      Application.delete_env(:media_centaur, FakeFacade)

      on_exit(fn ->
        if original, do: Application.put_env(:media_centaur, FakeFacade, original)
      end)

      :ok
    end

    test "returns the Linux impl on Linux" do
      assert Platform.pick_impl(
               FakeFacade,
               [linux: FakeLinux, darwin: FakeDarwin],
               os_type: {:unix, :linux}
             ) == FakeLinux
    end

    test "returns the macOS impl on Darwin" do
      assert Platform.pick_impl(
               FakeFacade,
               [linux: FakeLinux, darwin: FakeDarwin],
               os_type: {:unix, :darwin}
             ) == FakeDarwin
    end

    test "treats unrecognized unix as linux (FreeBSD, NetBSD, etc.)" do
      # Belief: any unix-flavor that isn't darwin is closer to linux.
      # If we ever add a real FreeBSD impl this assumption will need
      # revisiting.
      assert Platform.pick_impl(
               FakeFacade,
               [linux: FakeLinux, darwin: FakeDarwin],
               os_type: {:unix, :freebsd}
             ) == FakeLinux
    end

    test "raises on non-unix OS (Windows is not a current target)" do
      assert_raise RuntimeError, ~r/unsupported OS for Platform/, fn ->
        Platform.pick_impl(
          FakeFacade,
          [linux: FakeLinux, darwin: FakeDarwin],
          os_type: {:win32, :nt}
        )
      end
    end

    test "uses real :os.type/0 when :os_type opt is omitted" do
      # On the CI runner this is {:unix, :linux} — verifies the
      # production no-opt path returns the Linux impl.
      assert Platform.pick_impl(FakeFacade, linux: FakeLinux, darwin: FakeDarwin) ==
               FakeLinux
    end
  end
end
