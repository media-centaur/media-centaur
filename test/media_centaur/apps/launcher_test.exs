defmodule MediaCentaur.Apps.LauncherTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Apps.Launcher

  describe "spawn_spec/1" do
    test "wraps the command in a detached setsid + sh invocation" do
      assert Launcher.spawn_spec("sample-app --flag") ==
               {"setsid", ["-f", "sh", "-c", "sample-app --flag"]}
    end

    test "passes the command through as a single opaque string" do
      command = ~s(env FOO="a b" sample-app 'quoted arg' && echo done)
      assert {"setsid", ["-f", "sh", "-c", ^command]} = Launcher.spawn_spec(command)
    end
  end
end
