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

  describe "rename/2" do
    test "renames under the display-name rules and broadcasts the changed player" do
      player = create_player(name: "Living room TV")
      Players.subscribe()

      assert {:ok, %Player{name: "Den TV"}} = Players.rename(player, "  Den TV ")
      assert_receive {:player_changed, %Events.PlayerChanged{player: %Player{name: "Den TV"}}}
      assert Players.get(player.id).name == "Den TV"

      assert {:error, :name_required} = Players.rename(player, "  ")
      assert {:error, :name_too_long} = Players.rename(player, String.duplicate("x", 51))
      assert Players.get(player.id).name == "Den TV"
    end
  end

  describe "what the host learns of a player" do
    @device %{
      "model" => "Sample TV 4K",
      "os" => "Android 12",
      "app_version" => "0.3.0",
      "form_factor" => "tv"
    }

    test "a connection records the address, the device's declaration and when" do
      player = create_player()
      Players.subscribe()

      assert :ok = Players.record_connect(player.id, %{address: "192.168.1.40", device: @device})
      assert_receive {:player_changed, %Events.PlayerChanged{player: %Player{} = changed}}

      assert %Player.Device{
               model: "Sample TV 4K",
               os: "Android 12",
               app_version: "0.3.0",
               form_factor: :tv
             } =
               changed.device

      assert changed.last_address == "192.168.1.40"
      assert %DateTime{} = changed.last_seen_at
      assert Players.get(player.id).device == changed.device
    end

    test "a connection with no declaration keeps the device it last declared" do
      player = create_player()
      :ok = Players.record_connect(player.id, %{address: "192.168.1.40", device: @device})
      :ok = Players.record_connect(player.id, %{address: "192.168.1.41", device: nil})

      reread = Players.get(player.id)
      assert reread.device.model == "Sample TV 4K"
      assert reread.last_address == "192.168.1.41"
    end

    test "a declaration's unknown form factor and overlong values are dropped, not stored" do
      player = create_player()

      device = %{"model" => String.duplicate("m", 200), "os" => "Android 12", "form_factor" => "toaster"}
      :ok = Players.record_connect(player.id, %{address: "192.168.1.40", device: device})

      reread = Players.get(player.id)
      assert reread.device.os == "Android 12"
      assert reread.device.model == nil
      assert reread.device.form_factor == nil
    end

    test "a disconnection moves last seen on and leaves the rest" do
      player = create_player()
      :ok = Players.record_connect(player.id, %{address: "192.168.1.40", device: @device})
      connected = Players.get(player.id)
      Players.subscribe()

      assert :ok = Players.record_disconnect(player.id)
      assert_receive {:player_changed, %Events.PlayerChanged{player: %Player{} = changed}}
      assert DateTime.after?(changed.last_seen_at, connected.last_seen_at)
      assert changed.last_address == "192.168.1.40"
      assert changed.device == connected.device
    end

    test "a player that is not paired records nothing and broadcasts nothing" do
      player = create_player()
      :ok = Players.remove(player)
      Players.subscribe()

      assert :ok = Players.record_connect(player.id, %{address: "192.168.1.40", device: @device})
      assert :ok = Players.record_disconnect(player.id)
      assert :ok = Players.record_user_agent(player.id, "Sample/1.0")
      refute_receive {:player_changed, _event}
    end

    test "the browser's user agent is recorded when it changes, and only then broadcast" do
      player = create_player()
      Players.subscribe()

      assert :ok = Players.record_user_agent(player.id, "Sample/1.0")
      assert_receive {:player_changed, %Events.PlayerChanged{player: %Player{user_agent: "Sample/1.0"}}}

      assert :ok = Players.record_user_agent(player.id, "Sample/1.0")
      refute_receive {:player_changed, _event}

      assert :ok = Players.record_user_agent(player.id, "Sample/2.0")
      assert_receive {:player_changed, %Events.PlayerChanged{player: %Player{user_agent: "Sample/2.0"}}}
    end
  end
end
