defmodule MediaCentaur.Settings.Config.BindAddressTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Settings.Config.BindAddress

  describe "parse/1" do
    test "a missing key binds to loopback" do
      assert BindAddress.parse(nil) == {:ok, {127, 0, 0, 1}}
    end

    test "an IPv4 literal" do
      assert BindAddress.parse("0.0.0.0") == {:ok, {0, 0, 0, 0}}
      assert BindAddress.parse("192.168.1.20") == {:ok, {192, 168, 1, 20}}
    end

    test "an IPv6 literal" do
      assert BindAddress.parse("::") == {:ok, {0, 0, 0, 0, 0, 0, 0, 0}}
    end

    test "anything else is an error that names the key" do
      assert {:error, message} = BindAddress.parse("living-room-pc")
      assert message =~ "`bind`"
      assert message =~ "living-room-pc"

      assert {:error, _message} = BindAddress.parse(2160)
    end
  end

  describe "loopback?/1" do
    test "IPv4 and IPv6 loopback, and IPv4 loopback mapped into IPv6" do
      assert BindAddress.loopback?({127, 0, 0, 1})
      assert BindAddress.loopback?({127, 0, 0, 2})
      assert BindAddress.loopback?({0, 0, 0, 0, 0, 0, 0, 1})
      assert BindAddress.loopback?({0, 0, 0, 0, 0, 65_535, 32_512, 1})
    end

    test "a LAN address is not" do
      refute BindAddress.loopback?({192, 168, 1, 20})
      refute BindAddress.loopback?({0, 0, 0, 0})
      refute BindAddress.loopback?({0, 0, 0, 0, 0, 0, 0, 0})
    end
  end
end
