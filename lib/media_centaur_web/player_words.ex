defmodule MediaCentaurWeb.PlayerWords do
  @moduledoc """
  How a player reads on Settings → Players and Status → Playback: what
  device it is (`device_line/1`), whether and when it was connected
  (`seen_line/3`) and the glyph for its form factor (`icon/1`).

  The device line puts each fact from its one source on the row: the
  app's declaration (`Player.Device`) for the model, OS and app version,
  and the browser's user agent for the browser its pages run in — or,
  for a device that never ran the app, for the whole description.
  `browser/1` reads a user agent no further than a name, a major version
  and a platform; an agent it does not recognise names nothing.
  """

  alias MediaCentaur.Format
  alias MediaCentaur.Players.Player

  @doc "Why a rename was refused."
  @spec error(:name_required | :name_too_long) :: String.t()
  def error(:name_required), do: "A player needs a name"
  def error(:name_too_long), do: "Names are at most #{MediaCentaur.DisplayName.max_length()} characters"

  @doc "The host player's name."
  @spec host_name() :: String.t()
  def host_name, do: "This computer"

  @doc "The device line: the declaration's facts and the browser, or the browser alone; nil when nothing is known."
  @spec device_line(Player.t()) :: String.t() | nil
  def device_line(%Player{device: %Player.Device{} = device, user_agent: user_agent}) do
    [
      device.model,
      device.os,
      device.app_version && "App #{device.app_version}",
      user_agent |> parse() |> browser_name()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  def device_line(%Player{user_agent: user_agent}), do: browser(user_agent)

  @doc ~s(The browser a user agent names: "Chrome 131 on Android 10", or "WebView 131" for an app's own pages.)
  @spec browser(String.t() | nil) :: String.t() | nil
  def browser(user_agent) do
    case parse(user_agent) do
      nil -> nil
      %{browser: "WebView"} = parsed -> browser_name(parsed)
      %{platform: nil} = parsed -> browser_name(parsed)
      %{platform: platform} = parsed -> "#{browser_name(parsed)} on #{platform}"
    end
  end

  @doc "Connected now, last seen when and from where, or never."
  @spec seen_line(Player.t(), boolean(), DateTime.t()) :: String.t()
  def seen_line(%Player{last_address: address}, true, _now), do: "Connected from #{address}"
  def seen_line(%Player{last_seen_at: nil}, false, _now), do: "Not connected yet"

  def seen_line(%Player{last_seen_at: at, last_address: address}, false, now),
    do: "Last seen #{Format.relative_ago(at, now: now, sub_minute: :just_now)} from #{address}"

  @doc "The glyph for a player: this computer, or the device's form factor; a browser when the app never said."
  @spec icon(Player.t() | :host) :: String.t()
  def icon(:host), do: "hero-computer-desktop"
  def icon(%Player{device: %Player.Device{form_factor: :tv}}), do: "hero-tv"
  def icon(%Player{device: %Player.Device{form_factor: :phone}}), do: "hero-device-phone-mobile"
  def icon(%Player{device: %Player.Device{form_factor: :tablet}}), do: "hero-device-tablet"
  def icon(%Player{}), do: "hero-globe-alt"

  defp browser_name(nil), do: nil
  defp browser_name(%{browser: browser, version: version}), do: "#{browser} #{version}"

  # Order matters: Edge and the WebView also say Chrome; Chrome also says Safari.
  @browsers [
    {"Edge", ~r/Edg\/(\d+)/},
    {"Firefox", ~r/Firefox\/(\d+)/},
    {"Chrome", ~r/Chrome\/(\d+)/},
    {"Safari", ~r/Version\/(\d+)[\d.]* (?:Mobile\/\S+ )?Safari/}
  ]

  defp parse(user_agent) when is_binary(user_agent) do
    Enum.find_value(@browsers, fn {browser, pattern} ->
      case Regex.run(pattern, user_agent) do
        [_match, version] ->
          %{browser: browser(browser, user_agent), version: version, platform: platform(user_agent)}

        nil ->
          nil
      end
    end)
  end

  defp parse(_user_agent), do: nil

  defp browser("Chrome", user_agent),
    do: if(String.contains?(user_agent, "; wv)"), do: "WebView", else: "Chrome")

  defp browser(browser, _user_agent), do: browser

  defp platform(user_agent) do
    cond do
      match = Regex.run(~r/Android (\d+)/, user_agent) -> "Android #{Enum.at(match, 1)}"
      match = Regex.run(~r/(?:iPhone|CPU) OS (\d+)/, user_agent) -> "iOS #{Enum.at(match, 1)}"
      String.contains?(user_agent, "Windows") -> "Windows"
      String.contains?(user_agent, "Mac OS X") -> "macOS"
      String.contains?(user_agent, "Linux") -> "Linux"
      true -> nil
    end
  end
end
