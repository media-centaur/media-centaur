defmodule MediaCentarr.Platform.Autostart.LaunchdTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Platform.Autostart.Launchd

  @default_label "com.media-centarr.app"

  # Scripted command runner — returns canned output for specific argv
  # shapes. Mirrors the pattern Systemd tests use; keeps the Linux CI
  # runner from ever invoking real `launchctl`.
  defp fake_cmd(script) do
    fn binary, args ->
      case script[{binary, args}] do
        nil -> {"unexpected call: #{binary} #{Enum.join(args, " ")}", 1}
        response -> response
      end
    end
  end

  defp fake_env(env), do: fn name -> Map.get(env, name) end

  # When NOT launchd-supervised — no LAUNCHD_SOCKET env, no parent
  # launchd domain — every probe should report the supervisor as
  # unavailable.
  defp no_launchd_context, do: [env_fn: fake_env(%{})]

  describe "state/1" do
    test "reports full state when launchd is available + label loaded + active" do
      uid = "501"

      cmd =
        fake_cmd(%{
          {"launchctl", ["print", "gui/#{uid}/#{@default_label}"]} =>
            {"com.media-centarr.app = {\n\tstate = running\n}\n", 0},
          {"id", ["-u"]} => {"#{uid}\n", 0}
        })

      env = fake_env(%{"LAUNCHD_SOCKET" => "/var/run/launchd_xxx.socket"})

      assert %{
               under_launchd: true,
               launchd_available: true,
               unit_installed: true,
               active: true
             } = Launchd.state(cmd_fn: cmd, env_fn: env)
    end

    test "reports launchd_available: false when LAUNCHD_SOCKET is absent" do
      assert %{launchd_available: false, unit_installed: false, active: false} =
               Launchd.state(no_launchd_context())
    end

    test "reports active: false when launchctl print fails (label not loaded)" do
      uid = "501"

      cmd =
        fake_cmd(%{
          {"launchctl", ["print", "gui/#{uid}/#{@default_label}"]} =>
            {"Could not find service \"com.media-centarr.app\"\n", 113},
          {"id", ["-u"]} => {"#{uid}\n", 0}
        })

      env = fake_env(%{"LAUNCHD_SOCKET" => "/var/run/launchd_xxx.socket"})

      assert %{launchd_available: true, unit_installed: false, active: false} =
               Launchd.state(cmd_fn: cmd, env_fn: env)
    end
  end

  describe "detected_unit/1" do
    test "returns the configured label when under launchd" do
      env = fake_env(%{"LAUNCHD_SOCKET" => "/var/run/launchd_xxx.socket"})

      assert Launchd.detected_unit(env_fn: env) == @default_label
    end

    test "returns nil when LAUNCHD_SOCKET is absent" do
      refute Launchd.detected_unit(no_launchd_context())
    end
  end

  describe "restart/1" do
    test "uses launchctl kickstart -k gui/<uid>/<label>" do
      uid = "501"
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})

        case {binary, args} do
          {"id", ["-u"]} -> {"#{uid}\n", 0}
          _ -> {"", 0}
        end
      end

      assert :ok = Launchd.restart(cmd_fn: cmd, env_fn: fake_env(%{}))

      assert_receive {:cmd_called, "launchctl", ["kickstart", "-k", "gui/" <> _]}
    end

    test "propagates an error tuple when launchctl exits non-zero" do
      cmd = fn binary, _args ->
        case binary do
          "id" -> {"501\n", 0}
          _ -> {"Couldn't kickstart service", 1}
        end
      end

      assert {:error, {:launchctl_failed, 1, _}} =
               Launchd.restart(cmd_fn: cmd, env_fn: fake_env(%{}))
    end
  end

  describe "stop/1" do
    test "issues bootout, returning :ok on success" do
      uid = "501"
      me = self()

      cmd = fn binary, args ->
        send(me, {:cmd_called, binary, args})

        case {binary, args} do
          {"id", ["-u"]} -> {"#{uid}\n", 0}
          _ -> {"", 0}
        end
      end

      assert :ok = Launchd.stop(cmd_fn: cmd, env_fn: fake_env(%{}))

      assert_receive {:cmd_called, "launchctl", ["bootout", "gui/" <> _, @default_label]}
    end
  end

  describe "status_output/1" do
    test "returns the textual output of `launchctl print` (even on non-zero exit)" do
      cmd = fn binary, _args ->
        case binary do
          "id" -> {"501\n", 0}
          "launchctl" -> {"com.media-centarr.app = {\n\tstate = running\n}\n", 0}
        end
      end

      assert {:ok, output} = Launchd.status_output(cmd_fn: cmd, env_fn: fake_env(%{}))
      assert output =~ "com.media-centarr.app"
      assert output =~ "running"
    end
  end

  describe "handoff_env_vars/0" do
    test "returns empty list — launchctl gui/<uid> resolves from caller's UID, no env handover needed" do
      assert Launchd.handoff_env_vars() == []
    end
  end

  describe "tarball_required_paths/0" do
    test "returns the launchd plist path that macOS release tarballs must contain" do
      assert Launchd.tarball_required_paths() == [
               "share/launchd/com.media-centarr.app.plist"
             ]
    end
  end
end
