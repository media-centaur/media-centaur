defmodule MediaCentarr.Playback.DisplayEnvTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Playback.DisplayEnv

  @moduletag :tmp_dir

  describe "resolve/1 — already-set env vars pass through" do
    test "passes through WAYLAND_DISPLAY when set" do
      assert {:ok, env} =
               DisplayEnv.resolve(
                 env: %{"WAYLAND_DISPLAY" => "wayland-1", "XDG_RUNTIME_DIR" => "/nonexistent"},
                 runtime_dir: "/nonexistent",
                 x11_dir: "/nonexistent"
               )

      assert {~c"WAYLAND_DISPLAY", ~c"wayland-1"} in env
    end

    test "passes through DISPLAY when set" do
      assert {:ok, env} =
               DisplayEnv.resolve(
                 env: %{"DISPLAY" => ":0"},
                 runtime_dir: "/nonexistent",
                 x11_dir: "/nonexistent"
               )

      assert {~c"DISPLAY", ~c":0"} in env
    end

    test "passes through both when both are set" do
      assert {:ok, env} =
               DisplayEnv.resolve(
                 env: %{"WAYLAND_DISPLAY" => "wayland-1", "DISPLAY" => ":0"},
                 runtime_dir: "/nonexistent",
                 x11_dir: "/nonexistent"
               )

      assert {~c"WAYLAND_DISPLAY", ~c"wayland-1"} in env
      assert {~c"DISPLAY", ~c":0"} in env
    end

    test "passes through XDG_RUNTIME_DIR alongside resolved display vars", %{tmp_dir: tmp_dir} do
      File.touch!(Path.join(tmp_dir, "wayland-1"))

      assert {:ok, env} =
               DisplayEnv.resolve(
                 env: %{"XDG_RUNTIME_DIR" => tmp_dir},
                 runtime_dir: tmp_dir,
                 x11_dir: "/nonexistent"
               )

      assert {~c"XDG_RUNTIME_DIR", String.to_charlist(tmp_dir)} in env
    end
  end

  describe "resolve/1 — Wayland socket fallback" do
    test "finds wayland-1 socket in runtime_dir", %{tmp_dir: tmp_dir} do
      File.touch!(Path.join(tmp_dir, "wayland-1"))

      assert {:ok, env} =
               DisplayEnv.resolve(env: %{}, runtime_dir: tmp_dir, x11_dir: "/nonexistent")

      assert {~c"WAYLAND_DISPLAY", ~c"wayland-1"} in env
    end

    test "prefers lowest-numbered wayland socket when multiple exist", %{tmp_dir: tmp_dir} do
      File.touch!(Path.join(tmp_dir, "wayland-2"))
      File.touch!(Path.join(tmp_dir, "wayland-0"))
      File.touch!(Path.join(tmp_dir, "wayland-5"))

      assert {:ok, env} =
               DisplayEnv.resolve(env: %{}, runtime_dir: tmp_dir, x11_dir: "/nonexistent")

      assert {~c"WAYLAND_DISPLAY", ~c"wayland-0"} in env
    end

    test "ignores non-wayland files in runtime_dir", %{tmp_dir: tmp_dir} do
      File.touch!(Path.join(tmp_dir, "wayland-1"))
      File.touch!(Path.join(tmp_dir, "wayland-1.lock"))
      File.touch!(Path.join(tmp_dir, "pulse"))
      File.touch!(Path.join(tmp_dir, "bus"))

      assert {:ok, env} =
               DisplayEnv.resolve(env: %{}, runtime_dir: tmp_dir, x11_dir: "/nonexistent")

      assert {~c"WAYLAND_DISPLAY", ~c"wayland-1"} in env
    end
  end

  describe "resolve/1 — X11 socket fallback" do
    test "synthesizes DISPLAY=:N from X11 socket", %{tmp_dir: tmp_dir} do
      x11_dir = Path.join(tmp_dir, "X11-unix")
      File.mkdir_p!(x11_dir)
      File.touch!(Path.join(x11_dir, "X0"))

      assert {:ok, env} = DisplayEnv.resolve(env: %{}, runtime_dir: "/nonexistent", x11_dir: x11_dir)

      assert {~c"DISPLAY", ~c":0"} in env
    end

    test "prefers lowest-numbered X11 socket", %{tmp_dir: tmp_dir} do
      x11_dir = Path.join(tmp_dir, "X11-unix")
      File.mkdir_p!(x11_dir)
      File.touch!(Path.join(x11_dir, "X3"))
      File.touch!(Path.join(x11_dir, "X0"))
      File.touch!(Path.join(x11_dir, "X1"))

      assert {:ok, env} = DisplayEnv.resolve(env: %{}, runtime_dir: "/nonexistent", x11_dir: x11_dir)

      assert {~c"DISPLAY", ~c":0"} in env
    end
  end

  describe "resolve/1 — failure" do
    test "returns :no_display when no env and no sockets", %{tmp_dir: tmp_dir} do
      empty_x11 = Path.join(tmp_dir, "X11-unix")
      File.mkdir_p!(empty_x11)

      assert {:error, :no_display} =
               DisplayEnv.resolve(env: %{}, runtime_dir: tmp_dir, x11_dir: empty_x11)
    end

    test "returns :no_display when runtime_dir does not exist" do
      assert {:error, :no_display} =
               DisplayEnv.resolve(
                 env: %{},
                 runtime_dir: "/var/empty/nope",
                 x11_dir: "/var/empty/nope"
               )
    end
  end

  describe "resolve/1 — defaults" do
    test "reads from System.get_env() and standard paths when called without opts" do
      tag =
        case DisplayEnv.resolve() do
          {:ok, env} when is_list(env) -> :ok
          {:error, :no_display} -> :error
        end

      assert tag in [:ok, :error]
    end
  end
end
