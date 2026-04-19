defmodule MediaCentarr.SelfUpdate.HandoffTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.SelfUpdate.Handoff

  describe "spawn_detached/2" do
    test "invokes the spawn function with argv-form args (no shell interpolation into script)" do
      target_ref = make_ref()
      me = self()

      spawn_fn = fn args ->
        send(me, {target_ref, args})
        :ok
      end

      staged = "/home/user/.cache/media-centarr/upgrade-staging/0.7.1"

      assert :ok = Handoff.spawn_detached(staged, spawn_fn: spawn_fn)

      assert_receive {^target_ref, args}
      assert is_list(args)

      # Locate the shell + script-body slot: "sh", "-c", <body>, then "--",
      # then the installer path as $1.
      script_idx = Enum.find_index(args, &(&1 == "-c"))
      assert script_idx, "expected an -c arg for sh"
      body = Enum.at(args, script_idx + 1)
      # The body must NOT interpolate the staged path — it references $1 only.
      refute String.contains?(body, staged)
      assert String.contains?(body, "\"$1\"")

      dashdash_idx = Enum.find_index(args, &(&1 == "--"))
      assert dashdash_idx > script_idx, "-- must come after the script body"

      installer = Enum.at(args, dashdash_idx + 1)
      log_file = Enum.at(args, dashdash_idx + 2)
      assert installer == Path.join(staged, "bin/media-centarr-install")
      assert log_file == Path.join(staged, "handoff.log")

      # Script body redirects the shell's own stdio to $2 (log file) at
      # the very first line. Without this, closed-stdio from Port.close
      # would SIGPIPE the installer before `systemctl restart` runs.
      assert String.contains?(body, "\"$2\"")
      assert String.contains?(body, "exec >>\"$2\" 2>&1")

      # And the final line execs the installer — replacing the shell so
      # the installer inherits the (already-redirected) stdio.
      assert String.contains?(body, ~s(exec "$1"))
    end

    test "script logs trace lines so a stuck handoff can be diagnosed after the fact" do
      me = self()
      spawn_fn = fn args -> send(me, {:argv, args}) end

      assert :ok = Handoff.spawn_detached("/staged", spawn_fn: spawn_fn)

      assert_receive {:argv, args}
      script_idx = Enum.find_index(args, &(&1 == "-c"))
      body = Enum.at(args, script_idx + 1)

      # Each phase of the handoff writes a distinct line to the log so
      # we can tell whether the shell ran, whether sleep completed, and
      # whether the exec happened.
      assert String.contains?(body, "handoff: started at")
      assert String.contains?(body, "handoff: execing")
    end

    test "paths containing shell metacharacters remain as single argv entries, not parsed" do
      me = self()
      spawn_fn = fn args -> send(me, {:argv, args}) end

      # A maliciously-named staging path (would be a bug if it ever reached us,
      # but defense in depth).
      staged = "/tmp/evil;rm -rf $HOME/.bashrc#"

      assert :ok = Handoff.spawn_detached(staged, spawn_fn: spawn_fn)

      assert_receive {:argv, args}
      dashdash_idx = Enum.find_index(args, &(&1 == "--"))
      installer = Enum.at(args, dashdash_idx + 1)
      # The semicolon and spaces must be preserved inside the single argv entry.
      assert installer == Path.join(staged, "bin/media-centarr-install")
      assert String.contains?(installer, ";")
    end

    test "setsid --fork forces a new session so the chain survives Port.close" do
      me = self()
      spawn_fn = fn args -> send(me, {:argv, args}) end

      assert :ok = Handoff.spawn_detached("/staged", spawn_fn: spawn_fn)

      assert_receive {:argv, args}
      assert "setsid" in args
      setsid_idx = Enum.find_index(args, &(&1 == "setsid"))
      # `--fork` must come right after `setsid` — otherwise setsid execs
      # in place without forking and can be killed with the parent.
      assert Enum.at(args, setsid_idx + 1) == "--fork"
    end

    test "env hardening: HOME + minimal PATH, env -i strips inherited env" do
      me = self()
      spawn_fn = fn args -> send(me, {:argv, args}) end

      assert :ok =
               Handoff.spawn_detached("/staged",
                 spawn_fn: spawn_fn,
                 env_getter: fn _ -> nil end
               )

      assert_receive {:argv, args}
      assert "env" in args
      assert "-i" in args
      assert Enum.any?(args, &String.starts_with?(&1, "HOME="))
      assert "PATH=/usr/bin:/bin" in args
    end

    # Regression: `systemctl --user` inside the detached shell silently
    # failed on real installs because `env -i` stripped the env vars
    # systemctl needs to reach the user's systemd instance. The resulting
    # failure mode — new release staged but service never restarted — is
    # exactly what the user reported. Pass-through is the fix.
    test "passes through XDG_RUNTIME_DIR + DBUS_SESSION_BUS_ADDRESS when set" do
      me = self()
      spawn_fn = fn args -> send(me, {:argv, args}) end

      env = %{
        "XDG_RUNTIME_DIR" => "/run/user/1000",
        "DBUS_SESSION_BUS_ADDRESS" => "unix:path=/run/user/1000/bus"
      }

      assert :ok =
               Handoff.spawn_detached("/staged",
                 spawn_fn: spawn_fn,
                 env_getter: fn name -> Map.get(env, name) end
               )

      assert_receive {:argv, args}
      assert "XDG_RUNTIME_DIR=/run/user/1000" in args

      assert "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus" in args
    end

    test "omits systemd env vars entirely when the caller's environment has none" do
      me = self()
      spawn_fn = fn args -> send(me, {:argv, args}) end

      assert :ok =
               Handoff.spawn_detached("/staged",
                 spawn_fn: spawn_fn,
                 env_getter: fn _ -> nil end
               )

      assert_receive {:argv, args}
      refute Enum.any?(args, &String.starts_with?(&1, "XDG_RUNTIME_DIR="))
      refute Enum.any?(args, &String.starts_with?(&1, "DBUS_SESSION_BUS_ADDRESS="))
    end

    test "returns :ok even when the spawn function returns an unexpected value" do
      spawn_fn = fn _args -> {:something, :weird} end
      assert :ok = Handoff.spawn_detached("/any", spawn_fn: spawn_fn)
    end
  end
end
