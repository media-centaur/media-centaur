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

    test "propagates an error tuple when systemctl exits non-zero" do
      cmd = fn _binary, _args -> {"Unit failed to restart", 1} end

      assert {:error, {:systemctl_failed, 1, "Unit failed to restart"}} =
               Service.restart(cmd_fn: cmd)
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
