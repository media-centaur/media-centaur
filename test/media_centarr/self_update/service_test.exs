defmodule MediaCentarr.SelfUpdate.ServiceTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.SelfUpdate.Service

  # A tiny scripted command runner: returns canned output based on the
  # argv pattern the implementation invokes. Keeps the tests deterministic
  # and hermetic — no real `systemctl` ever runs.
  defp fake_cmd(script) do
    fn binary, args ->
      case script[{binary, args}] do
        nil -> {"unexpected call: #{binary} #{Enum.join(args, " ")}", 1}
        response -> response
      end
    end
  end

  # Fake env reader for the detection helpers. Takes a map of var name -> value.
  defp fake_env(env), do: fn name -> Map.get(env, name) end

  # Fake /proc/self/cgroup reader. Takes `{:ok, binary()}` or `{:error, term()}`.
  defp fake_cgroup(response), do: fn -> response end

  # cgroup v2 path for the dev unit, matching what systemd produces in
  # practice for a --user unit nested under app.slice.
  @dev_cgroup "0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centarr-dev.service\n"
  @prod_cgroup "0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centarr.service\n"
  @showcase_cgroup "0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centarr-showcase.service\n"
  # cgroup v1 multi-line shape (legacy; kept for robustness)
  @v1_cgroup """
  12:freezer:/
  11:perf_event:/
  1:name=systemd:/user.slice/user-1000.slice/user@1000.service/app.slice/media-centarr.service
  0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centarr.service
  """

  describe "state/1" do
    test "reports full state when systemd is available, unit installed, active, enabled" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"HOME=/home/user\n", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"UNIT FILE                STATE   VENDOR PRESET\nmedia-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"enabled\n", 0}
        })

      assert %{
               systemd_available: true,
               unit_installed: true,
               active: true,
               enabled: true
             } = Service.state(cmd_fn: cmd)
    end

    test "reports systemd_available: false when show-environment fails" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"Failed to connect", 1}
        })

      assert %{systemd_available: false, unit_installed: false, active: false, enabled: false} =
               Service.state(cmd_fn: cmd)
    end

    test "reports active: false when is-active exits non-zero" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"media-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"inactive\n", 3},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"enabled\n", 0}
        })

      assert %{active: false, enabled: true} = Service.state(cmd_fn: cmd)
    end

    test "reports unit_installed: false when list-unit-files doesn't mention our unit" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"0 unit files listed.\n", 1},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"inactive\n", 3},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"disabled\n", 1}
        })

      assert %{unit_installed: false} = Service.state(cmd_fn: cmd)
    end
  end

  describe "state/1 — detection via INVOCATION_ID + cgroup" do
    test "under_systemd: true and unit_name from cgroup when INVOCATION_ID is set (dev unit)" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr-dev.service", "--no-pager"]} =>
            {"media-centarr-dev.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr-dev.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr-dev.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "deadbeefcafebabe0123456789abcdef"}),
          cgroup_reader: fake_cgroup({:ok, @dev_cgroup})
        )

      assert %{
               under_systemd: true,
               unit_name: "media-centarr-dev.service",
               systemd_available: true,
               unit_installed: true,
               active: true,
               enabled: true
             } = state
    end

    test "detects the showcase unit from cgroup" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr-showcase.service", "--no-pager"]} =>
            {"media-centarr-showcase.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr-showcase.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr-showcase.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:ok, @showcase_cgroup})
        )

      assert state.unit_name == "media-centarr-showcase.service"
      assert state.under_systemd == true
      assert state.active == true
    end

    test "under_systemd: false and unit_name: nil when INVOCATION_ID is absent" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"media-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"inactive\n", 3},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{}),
          cgroup_reader: fake_cgroup({:ok, @prod_cgroup})
        )

      assert state.under_systemd == false
      assert state.unit_name == nil
    end

    test "under_systemd: true, unit_name: nil when cgroup read fails" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"media-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:error, :enoent})
        )

      assert state.under_systemd == true
      assert state.unit_name == nil
      # Falls back to the compile-time default unit for systemctl probes.
      assert state.unit_installed == true
      assert state.active == true
    end

    test "parses cgroup v1 shape with name=systemd line" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"media-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:ok, @v1_cgroup})
        )

      assert state.unit_name == "media-centarr.service"
    end

    test "unit_name: nil when cgroup has no *.service segment (e.g. init.scope)" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"media-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:ok, "0::/init.scope\n"})
        )

      assert state.unit_name == nil
    end

    test "unit_name: nil when cgroup contents are empty" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centarr.service", "--no-pager"]} =>
            {"media-centarr.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centarr.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centarr.service"]} => {"active\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{}),
          cgroup_reader: fake_cgroup({:ok, ""})
        )

      assert state.unit_name == nil
    end
  end

  describe "restart/1" do
    test "calls systemctl --user --no-block restart and returns :ok on success" do
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})
        {"", 0}
      end

      assert :ok = Service.restart(cmd_fn: cmd)

      assert_receive {:cmd_called, "systemctl",
                      ["--user", "--no-block", "restart", "media-centarr.service"]}
    end

    test "targets the cgroup-detected unit when available" do
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})
        {"", 0}
      end

      assert :ok =
               Service.restart(
                 cmd_fn: cmd,
                 cgroup_reader: fake_cgroup({:ok, @dev_cgroup})
               )

      assert_receive {:cmd_called, "systemctl",
                      ["--user", "--no-block", "restart", "media-centarr-dev.service"]}
    end

    test "propagates an error tuple when systemctl exits non-zero" do
      cmd = fn _binary, _args -> {"Unit failed to restart", 1} end

      assert {:error, {:systemctl_failed, 1, "Unit failed to restart"}} =
               Service.restart(cmd_fn: cmd)
    end
  end

  describe "default cmd — env option sanity" do
    # Regression guard: a previous revision passed `{name, false}` to the
    # `env:` option of `System.cmd/3` to unset secrets. Elixir 1.19 raises
    # `FunctionClauseError` inside `String.to_charlist/1` for any non-binary
    # env value, which our rescue clause masked as exit 127 — silently
    # making every `systemctl` probe look like a missing binary.
    test "state/0 does not crash when the real System.cmd is exercised" do
      # No injection: this exercises the default_cmd path. The test isn't
      # asserting on the systemctl output (may or may not be present on CI);
      # it only asserts the call graph doesn't raise.
      assert %{} = MediaCentarr.SelfUpdate.Service.state()
    end
  end

  describe "stop/1" do
    test "uses --no-block stop and returns :ok on success" do
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})
        {"", 0}
      end

      assert :ok = Service.stop(cmd_fn: cmd)

      assert_receive {:cmd_called, "systemctl",
                      ["--user", "--no-block", "stop", "media-centarr.service"]}
    end

    test "targets the cgroup-detected unit when available" do
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})
        {"", 0}
      end

      assert :ok =
               Service.stop(
                 cmd_fn: cmd,
                 cgroup_reader: fake_cgroup({:ok, @dev_cgroup})
               )

      assert_receive {:cmd_called, "systemctl",
                      ["--user", "--no-block", "stop", "media-centarr-dev.service"]}
    end
  end

  describe "status_output/1" do
    test "returns the textual output even when systemctl exits non-zero" do
      # systemctl status returns non-zero for inactive/failed units but
      # the output is still useful — the UI wants to show it either way.
      cmd = fn _binary, _args ->
        {"● media-centarr.service - Media Centarr\n     Loaded: loaded\n     Active: inactive\n", 3}
      end

      assert {:ok, output} = Service.status_output(cmd_fn: cmd)
      assert output =~ "media-centarr.service"
      assert output =~ "inactive"
    end
  end
end
