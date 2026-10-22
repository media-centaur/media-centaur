defmodule MediaCentaurWeb.SettingsLive.PlayersSectionTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.SettingsLive.PlayersSection

  @lan [{192, 168, 1, 5}, {10, 0, 0, 7}]

  describe "reach/2" do
    test "bound to loopback, other devices cannot reach the install" do
      assert PlayersSection.reach([ip: {127, 0, 0, 1}, port: 2160], @lan) == :loopback
    end

    test "bound to every interface, every LAN address with the port is a way in" do
      assert PlayersSection.reach([ip: {0, 0, 0, 0}, port: 2160], @lan) ==
               {:addresses, ["http://192.168.1.5:2160", "http://10.0.0.7:2160"]}

      assert PlayersSection.reach([ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: 2160], @lan) ==
               {:addresses, ["http://192.168.1.5:2160", "http://10.0.0.7:2160"]}
    end

    test "bound to one interface, that address alone" do
      assert PlayersSection.reach([ip: {10, 0, 0, 7}, port: 4003], @lan) ==
               {:addresses, ["http://10.0.0.7:4003"]}
    end

    test "bound to every interface with no LAN address found" do
      assert PlayersSection.reach([ip: {0, 0, 0, 0}, port: 2160], []) == {:addresses, []}
    end
  end
end
