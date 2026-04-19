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

      # Script body redirects the installer's stdout+stderr to $2 (log
      # file). Without this, closed-stdio from Port.close would SIGPIPE
      # the installer before `systemctl restart` runs.
      assert String.contains?(body, "\"$2\"")
      assert String.contains?(body, ">\"$2\" 2>&1")
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

      assert :ok = Handoff.spawn_detached("/staged", spawn_fn: spawn_fn)

      assert_receive {:argv, args}
      assert "env" in args
      assert "-i" in args
      assert Enum.any?(args, &String.starts_with?(&1, "HOME="))
      assert "PATH=/usr/bin:/bin" in args
    end

    test "returns :ok even when the spawn function returns an unexpected value" do
      spawn_fn = fn _args -> {:something, :weird} end
      assert :ok = Handoff.spawn_detached("/any", spawn_fn: spawn_fn)
    end
  end
end
