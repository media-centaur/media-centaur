defmodule MediaCentarr.ErrorReports.EnvMetadata do
  @moduledoc """
  Collects environment fields for an error report — app version,
  Erlang/Elixir, OS, locale, uptime. Pure: no PubSub, no DB.
  """

  @type t :: %{
          app_version: binary(),
          otp_release: binary(),
          elixir_version: binary(),
          os: binary(),
          locale: binary(),
          uptime: binary()
        }

  @spec collect() :: t()
  def collect do
    %{
      app_version: to_string(Application.spec(:media_centarr, :vsn)),
      otp_release: to_string(:erlang.system_info(:otp_release)),
      elixir_version: System.version(),
      os: os_string(),
      locale: System.get_env("LANG") || "unknown",
      uptime: uptime_string()
    }
  end

  @spec render(t()) :: binary()
  def render(%{} = meta) do
    String.trim_trailing("""
    App:     media-centarr #{meta.app_version}
    Erlang:  OTP #{meta.otp_release} / Elixir #{meta.elixir_version}
    OS:      #{meta.os}
    Locale:  #{meta.locale}
    Uptime:  #{meta.uptime}
    """)
  end

  defp os_string do
    {family, name} = :os.type()
    version = format_os_version(:os.version())
    arch = to_string(:erlang.system_info(:system_architecture))
    "#{family}/#{name} #{version} (#{arch})"
  end

  defp format_os_version({maj, min, patch}), do: "#{maj}.#{min}.#{patch}"
  defp format_os_version(other) when is_binary(other) or is_list(other), do: to_string(other)
  defp format_os_version(_), do: "unknown"

  defp uptime_string do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    seconds = div(uptime_ms, 1_000)

    cond do
      seconds >= 86_400 ->
        "#{div(seconds, 86_400)}d #{div(rem(seconds, 86_400), 3_600)}h"

      seconds >= 3_600 ->
        "#{div(seconds, 3_600)}h #{div(rem(seconds, 3_600), 60)}m"

      seconds >= 60 ->
        "#{div(seconds, 60)}m #{rem(seconds, 60)}s"

      true ->
        "#{seconds}s"
    end
  end
end
