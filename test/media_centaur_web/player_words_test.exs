defmodule MediaCentaurWeb.PlayerWordsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Players.Player
  alias MediaCentaurWeb.PlayerWords

  @webview "Mozilla/5.0 (Linux; Android 12; Sample TV Build/STTE.230215.005; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.135 Mobile Safari/537.36"
  @chrome_android "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
  @firefox_linux "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0"
  @safari_iphone "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
  @edge_windows "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.2903.86"

  @device %Player.Device{model: "Sample TV 4K", os: "Android 12", app_version: "0.3.0", form_factor: :tv}

  describe "browser/1" do
    test "names the browser and its major version, and the platform it runs on" do
      assert PlayerWords.browser(@webview) == "WebView 131"
      assert PlayerWords.browser(@chrome_android) == "Chrome 131 on Android 10"
      assert PlayerWords.browser(@firefox_linux) == "Firefox 133 on Linux"
      assert PlayerWords.browser(@safari_iphone) == "Safari 17 on iOS 17"
      assert PlayerWords.browser(@edge_windows) == "Edge 131 on Windows"
    end

    test "an agent it cannot read, or none, names nothing" do
      assert PlayerWords.browser("curl/8.0") == nil
      assert PlayerWords.browser(nil) == nil
    end
  end

  describe "device_line/1" do
    test "the app's declaration, then the browser its pages run in" do
      player = %Player{device: @device, user_agent: @webview}
      assert PlayerWords.device_line(player) == "Sample TV 4K · Android 12 · App 0.3.0 · WebView 131"
    end

    test "a device that never ran the app is described by its browser alone" do
      assert PlayerWords.device_line(%Player{user_agent: @chrome_android}) == "Chrome 131 on Android 10"
    end

    test "nothing learned yet describes nothing" do
      assert PlayerWords.device_line(%Player{}) == nil
    end
  end

  describe "seen_line/3" do
    @now ~U[2026-11-07 12:00:00.000000Z]

    test "a connected player says so, with the address it came from" do
      player = %Player{last_address: "192.168.1.40", last_seen_at: @now}
      assert PlayerWords.seen_line(player, true, @now) == "Connected from 192.168.1.40"
    end

    test "a player not connected says when and where it was last seen" do
      player = %Player{last_address: "192.168.1.40", last_seen_at: DateTime.add(@now, -3, :day)}
      assert PlayerWords.seen_line(player, false, @now) == "Last seen 3d ago from 192.168.1.40"
    end

    test "a player that has never connected says that" do
      assert PlayerWords.seen_line(%Player{}, false, @now) == "Not connected yet"
    end
  end

  test "icon/1 draws the device's form factor" do
    assert PlayerWords.icon(%Player{device: @device}) == "hero-tv"

    assert PlayerWords.icon(%Player{device: %{@device | form_factor: :phone}}) ==
             "hero-device-phone-mobile"

    assert PlayerWords.icon(%Player{device: %{@device | form_factor: :tablet}}) == "hero-device-tablet"
    assert PlayerWords.icon(%Player{}) == "hero-globe-alt"
    assert PlayerWords.icon(:host) == "hero-computer-desktop"
  end
end
