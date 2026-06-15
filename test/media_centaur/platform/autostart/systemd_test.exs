defmodule MediaCentaur.Platform.Autostart.SystemdTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Platform.Autostart.Systemd, as: Service

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

  # Isolation for tests that exercise the default-unit path. Without these,
  # the production defaults read the host's real INVOCATION_ID and
  # /proc/self/cgroup — which on GitHub's hosted-compute runners resolves
  # to "hosted-compute-agent.service" and diverts every systemctl probe to
  # the wrong unit name.
  defp no_systemd_context, do: [env_fn: fake_env(%{}), cgroup_reader: fake_cgroup({:error, :enoent})]

  # cgroup v2 path for the dev unit, matching what systemd produces in
  # practice for a --user unit nested under app.slice.
  @dev_cgroup "0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centaur-dev.service\n"
  @prod_cgroup "0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centaur.service\n"
  @showcase_cgroup "0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centaur-showcase.service\n"
  # cgroup v1 multi-line shape (legacy; kept for robustness)
  @v1_cgroup """
  12:freezer:/
  11:perf_event:/
  1:name=systemd:/user.slice/user-1000.slice/user@1000.service/app.slice/media-centaur.service
  0::/user.slice/user-1000.slice/user@1000.service/app.slice/media-centaur.service
  """

  describe "state/1" do
    test "returns the OS-neutral key set shared with the launchd impl" do
      cmd = fake_cmd(%{{"systemctl", ["--user", "show-environment"]} => {"Failed", 1}})
      keys = Service.state(cmd_fn: cmd) |> Map.keys() |> Enum.sort()

      assert keys ==
               Enum.sort([
                 :active,
                 :enabled,
                 :supervisor_available,
                 :under_supervisor,
                 :unit_installed,
                 :unit_name
               ])
    end

    test "reports full state when systemd is available, unit installed, active, enabled" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"HOME=/home/user\n", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"UNIT FILE                STATE   VENDOR PRESET\nmedia-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"enabled\n", 0}
        })

      assert %{
               supervisor_available: true,
               unit_installed: true,
               active: true,
               enabled: true
             } = Service.state(Keyword.put(no_systemd_context(), :cmd_fn, cmd))
    end

    test "reports supervisor_available: false when show-environment fails" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"Failed to connect", 1}
        })

      assert %{supervisor_available: false, unit_installed: false, active: false, enabled: false} =
               Service.state(cmd_fn: cmd)
    end

    test "reports active: false when is-active exits non-zero" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"media-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"inactive\n", 3},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"enabled\n", 0}
        })

      assert %{active: false, enabled: true} =
               Service.state(Keyword.put(no_systemd_context(), :cmd_fn, cmd))
    end

    test "reports unit_installed: false when list-unit-files doesn't mention our unit" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"0 unit files listed.\n", 1},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"inactive\n", 3},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"disabled\n", 1}
        })

      assert %{unit_installed: false} = Service.state(cmd_fn: cmd)
    end
  end

  describe "state/1 — detection via INVOCATION_ID + cgroup" do
    test "under_supervisor: true and unit_name from cgroup when INVOCATION_ID is set (dev unit)" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur-dev.service", "--no-pager"]} =>
            {"media-centaur-dev.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur-dev.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur-dev.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "deadbeefcafebabe0123456789abcdef"}),
          cgroup_reader: fake_cgroup({:ok, @dev_cgroup})
        )

      assert %{
               under_supervisor: true,
               unit_name: "media-centaur-dev.service",
               supervisor_available: true,
               unit_installed: true,
               active: true,
               enabled: true
             } = state
    end

    test "detects the showcase unit from cgroup" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur-showcase.service", "--no-pager"]} =>
            {"media-centaur-showcase.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur-showcase.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur-showcase.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:ok, @showcase_cgroup})
        )

      assert state.unit_name == "media-centaur-showcase.service"
      assert state.under_supervisor == true
      assert state.active == true
    end

    test "under_supervisor: false and unit_name: nil when INVOCATION_ID is absent" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"media-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"inactive\n", 3},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{}),
          cgroup_reader: fake_cgroup({:ok, @prod_cgroup})
        )

      assert state.under_supervisor == false
      assert state.unit_name == nil
    end

    test "under_supervisor: true, unit_name: nil when cgroup read fails" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"media-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:error, :enoent})
        )

      assert state.under_supervisor == true
      assert state.unit_name == nil
      # Falls back to the compile-time default unit for systemctl probes.
      assert state.unit_installed == true
      assert state.active == true
    end

    test "parses cgroup v1 shape with name=systemd line" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"media-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"enabled\n", 0}
        })

      state =
        Service.state(
          cmd_fn: cmd,
          env_fn: fake_env(%{"INVOCATION_ID" => "x"}),
          cgroup_reader: fake_cgroup({:ok, @v1_cgroup})
        )

      assert state.unit_name == "media-centaur.service"
    end

    test "unit_name: nil when cgroup has no *.service segment (e.g. init.scope)" do
      cmd =
        fake_cmd(%{
          {"systemctl", ["--user", "show-environment"]} => {"", 0},
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"media-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"enabled\n", 0}
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
          {"systemctl", ["--user", "list-unit-files", "media-centaur.service", "--no-pager"]} =>
            {"media-centaur.service    enabled -\n", 0},
          {"systemctl", ["--user", "is-active", "media-centaur.service"]} => {"active\n", 0},
          {"systemctl", ["--user", "is-enabled", "media-centaur.service"]} => {"active\n", 0}
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

      assert :ok = Service.restart(Keyword.put(no_systemd_context(), :cmd_fn, cmd))

      assert_receive {:cmd_called, "systemctl",
                      ["--user", "--no-block", "restart", "media-centaur.service"]}
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
                      ["--user", "--no-block", "restart", "media-centaur-dev.service"]}
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
      assert %{} = MediaCentaur.Platform.Autostart.Systemd.state()
    end
  end

  describe "stop/1" do
    test "uses --no-block stop and returns :ok on success" do
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})
        {"", 0}
      end

      assert :ok = Service.stop(Keyword.put(no_systemd_context(), :cmd_fn, cmd))

      assert_receive {:cmd_called, "systemctl",
                      ["--user", "--no-block", "stop", "media-centaur.service"]}
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
                      ["--user", "--no-block", "stop", "media-centaur-dev.service"]}
    end
  end

  describe "status_output/1" do
    test "returns the textual output even when systemctl exits non-zero" do
      # systemctl status returns non-zero for inactive/failed units but
      # the output is still useful — the UI wants to show it either way.
      cmd = fn _binary, _args ->
        {"● media-centaur.service - Media Centaur\n     Loaded: loaded\n     Active: inactive\n", 3}
      end

      assert {:ok, output} = Service.status_output(cmd_fn: cmd)
      assert output =~ "media-centaur.service"
      assert output =~ "inactive"
    end
  end

  describe "handoff_env_vars/0" do
    # The detached installer's `systemctl --user` needs these vars
    # forwarded through `env -i` to reach the user's systemd. Without
    # them the installer's autostart probe fails, no unit gets
    # restarted, and the new release stages on disk but the running
    # BEAM keeps running.
    test "returns the systemd-required env-var names" do
      vars = Service.handoff_env_vars()

      assert "XDG_RUNTIME_DIR" in vars
      assert "DBUS_SESSION_BUS_ADDRESS" in vars
      assert "XDG_DATA_DIRS" in vars
      assert "XDG_CONFIG_DIRS" in vars
    end
  end

  describe "tarball_required_paths/0" do
    test "returns the systemd unit-file path that release tarballs must contain" do
      assert Service.tarball_required_paths() == [
               "share/systemd/media-centaur.service"
             ]
    end
  end
end
