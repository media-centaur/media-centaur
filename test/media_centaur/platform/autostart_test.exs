defmodule MediaCentaur.Platform.AutostartTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.Platform.Autostart

  # async: false because we mutate Application env. Each test rolls
  # back its override in `on_exit`.

  defmodule FakeImpl do
    @behaviour MediaCentaur.Platform.Autostart

    @impl true
    def state(_opts \\ []), do: %{available: false, unit: "fake.service"}

    @impl true
    def detected_unit(_opts \\ []), do: "fake.service"

    @impl true
    def restart(_opts \\ []), do: :ok

    @impl true
    def stop(_opts \\ []), do: :ok

    @impl true
    def status_output(_opts \\ []), do: {:ok, "fake status"}

    @impl true
    def handoff_env_vars, do: ["FAKE_ENV_VAR"]

    @impl true
    def tarball_required_paths, do: ["share/fake/foo"]
  end

  describe "facade dispatch" do
    setup do
      original = Application.get_env(:media_centaur, Autostart)
      Application.put_env(:media_centaur, Autostart, FakeImpl)

      on_exit(fn ->
        if original do
          Application.put_env(:media_centaur, Autostart, original)
        else
          Application.delete_env(:media_centaur, Autostart)
        end
      end)

      :ok
    end

    test "state/0 delegates to the configured impl" do
      assert %{available: false, unit: "fake.service"} = Autostart.state()
    end

    test "detected_unit/0 delegates" do
      assert "fake.service" = Autostart.detected_unit()
    end

    test "restart/0 delegates" do
      assert :ok = Autostart.restart()
    end

    test "stop/0 delegates" do
      assert :ok = Autostart.stop()
    end

    test "status_output/0 delegates" do
      assert {:ok, "fake status"} = Autostart.status_output()
    end

    test "handoff_env_vars/0 delegates" do
      assert ["FAKE_ENV_VAR"] = Autostart.handoff_env_vars()
    end

    test "tarball_required_paths/0 delegates" do
      assert ["share/fake/foo"] = Autostart.tarball_required_paths()
    end
  end

  describe "default impl" do
    test "defaults to Systemd when no impl is configured" do
      original = Application.get_env(:media_centaur, Autostart)
      Application.delete_env(:media_centaur, Autostart)

      on_exit(fn ->
        if original, do: Application.put_env(:media_centaur, Autostart, original)
      end)

      # Sanity: handoff_env_vars/0 is pure and cheap, returns the
      # systemd-required list. No shell-out involved.
      vars = Autostart.handoff_env_vars()
      assert "XDG_RUNTIME_DIR" in vars
    end
  end
end
