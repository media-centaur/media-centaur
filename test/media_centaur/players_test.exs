defmodule MediaCentaur.PlayersTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Players
  alias MediaCentaur.Players.Events
  alias MediaCentaur.Players.Pairing
  alias MediaCentaur.Players.Player

  describe "pairing" do
    test "start_pairing opens one code, replacing any open one, and broadcasts it" do
      Players.subscribe()

      first = Players.start_pairing()
      assert %Pairing.Code{code: <<_::binary-size(6)>>} = first
      assert_receive {:pairing_changed, %Events.PairingChanged{code: ^first}}
      assert Players.pairing() == first

      second = Players.start_pairing()
      assert second != first
      assert Players.pairing() == second
      assert {:error, :invalid_code} = Players.pair(first.code, "Living room TV")
    end

    test "pair with the open code adds the player, consumes the code, and broadcasts" do
      Players.subscribe()
      %Pairing.Code{code: code} = Players.start_pairing()

      assert {:ok, %Player{name: "Living room TV"} = player} = Players.pair(code, "  Living room TV ")
      assert_receive {:player_paired, %Events.PlayerPaired{player: %Player{id: id}}}
      assert id == player.id
      assert_receive {:pairing_changed, %Events.PairingChanged{code: nil}}
      assert Players.pairing() == nil

      assert {:error, :invalid_code} = Players.pair(code, "Bedroom TV")
      assert [%Player{id: ^id}] = Players.list()
      assert Players.get(id).name == "Living room TV"
    end

    test "pair checks the name and leaves the code open on a bad name" do
      %Pairing.Code{code: code} = Players.start_pairing()

      assert {:error, :name_required} = Players.pair(code, "   ")
      assert {:error, :name_too_long} = Players.pair(code, String.duplicate("x", 51))
      assert Players.pairing() != nil
    end

    test "pair with no code open is invalid" do
      assert Players.pairing() == nil
      assert {:error, :invalid_code} = Players.pair("123456", "Living room TV")
    end

    test "too many wrong codes cancel the pairing" do
      Players.subscribe()
      %Pairing.Code{code: code} = Players.start_pairing()
      wrong = if code == "000000", do: "000001", else: "000000"

      for _attempt <- 1..(Pairing.Code.max_attempts() - 1) do
        assert {:error, :invalid_code} = Players.pair(wrong, "Living room TV")
        assert Players.pairing() != nil
      end

      assert {:error, :invalid_code} = Players.pair(wrong, "Living room TV")
      assert Players.pairing() == nil
      assert_receive {:pairing_changed, %Events.PairingChanged{code: nil}}
      assert {:error, :invalid_code} = Players.pair(code, "Living room TV")
    end

    test "cancel_pairing closes the code and broadcasts" do
      Players.subscribe()
      Players.start_pairing()
      assert :ok = Players.cancel_pairing()
      assert Players.pairing() == nil
      assert_receive {:pairing_changed, %Events.PairingChanged{code: nil}}
      assert :ok = Players.cancel_pairing()
    end
  end

  describe "list/0, get/1, remove/1" do
    test "players list oldest first; get answers nil for unknown or malformed ids" do
      first = create_player(name: "Living room TV")
      second = create_player(name: "Bedroom TV")

      assert ["Living room TV", "Bedroom TV"] = Enum.map(Players.list(), & &1.name)
      assert Players.get(first.id).id == first.id
      assert Players.get(second.id).id == second.id
      assert Players.get(Ecto.UUID.generate()) == nil
      assert Players.get("not-a-uuid") == nil
      assert Players.get(nil) == nil
    end

    test "remove deletes the player and broadcasts; removing again is a no-op" do
      Players.subscribe()
      player = create_player(name: "Living room TV")

      assert :ok = Players.remove(player)
      assert_receive {:player_removed, %Events.PlayerRemoved{id: id}}
      assert id == player.id
      assert Players.get(player.id) == nil
      assert Players.list() == []

      assert :ok = Players.remove(player)
      refute_receive {:player_removed, _event}
    end
  end
end
