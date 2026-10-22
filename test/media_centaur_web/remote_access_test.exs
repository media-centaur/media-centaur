defmodule MediaCentaurWeb.RemoteAccessTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaurWeb.RemoteAccess

  @lan {192, 168, 1, 20}

  test "a loopback address is the host, whatever the session holds" do
    assert RemoteAccess.admit({127, 0, 0, 1}, nil) == {:ok, :host}
    assert RemoteAccess.admit({0, 0, 0, 0, 0, 0, 0, 1}, "anything") == {:ok, :host}
  end

  test "a LAN address is the paired player its session names" do
    player = create_player(name: "Living room TV")
    assert {:ok, %{id: id}} = RemoteAccess.admit(@lan, player.id)
    assert id == player.id
  end

  test "a LAN address with no, an unknown, or a removed player is unpaired" do
    assert RemoteAccess.admit(@lan, nil) == :unpaired
    assert RemoteAccess.admit(@lan, Ecto.UUID.generate()) == :unpaired
    assert RemoteAccess.admit(@lan, "not-a-uuid") == :unpaired

    player = create_player(name: "Living room TV")
    :ok = MediaCentaur.Players.remove(player)
    assert RemoteAccess.admit(@lan, player.id) == :unpaired
  end
end
