defmodule MediaCentarr.SecretTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Secret

  describe "wrap/1" do
    test "wraps a binary as a Secret" do
      assert %Secret{} = Secret.wrap("hunter2")
    end

    test "returns nil for nil (so callers don't have to special-case unset)" do
      assert Secret.wrap(nil) == nil
    end

    test "is idempotent — wrapping a Secret returns the same Secret" do
      secret = Secret.wrap("x")
      assert Secret.wrap(secret) == secret
    end
  end

  describe "expose/1" do
    test "returns the underlying string" do
      assert Secret.expose(Secret.wrap("hunter2")) == "hunter2"
    end

    test "passes nil through" do
      assert Secret.expose(nil) == nil
    end
  end

  describe "present?/1" do
    test "true when wrapped value is a non-empty string" do
      assert Secret.present?(Secret.wrap("x"))
    end

    test "false for nil, an unwrapped Secret nil, or an empty string" do
      refute Secret.present?(nil)
      refute Secret.present?(Secret.wrap(""))
    end
  end

  describe "Inspect protocol" do
    test "redacts the value in inspect/2 output" do
      assert inspect(Secret.wrap("hunter2")) == "#Secret<***>"
    end

    test "redacts even inside a containing map (the crash-dump scenario)" do
      assigns = %{config: %{api_key: Secret.wrap("hunter2"), other: "visible"}}
      output = inspect(assigns)
      refute output =~ "hunter2"
      assert output =~ "#Secret<***>"
      assert output =~ "visible"
    end
  end

  describe "String.Chars protocol" do
    test "is intentionally NOT implemented — interpolation should crash loudly" do
      secret = Secret.wrap("hunter2")

      assert_raise Protocol.UndefinedError, fn ->
        "#{secret}"
      end
    end
  end
end
