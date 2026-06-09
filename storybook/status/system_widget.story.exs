defmodule MediaCentaurWeb.Storybook.Status.SystemWidget do
  @moduledoc "Storybook coverage for the System runtime-vitals widget."
  use PhoenixStorybook.Story, :component

  def function, do: &MediaCentaurWeb.ActivityWidgetComponents.system_widget/1

  def render_source, do: :function

  def variations do
    host = %{
      otp: "27",
      elixir: "1.18.1",
      os: "unix/linux 6.0.10 (x86_64-pc-linux-gnu)",
      version: "0.86.1"
    }

    db = %{size_bytes: 148_897_792, wal_bytes: 4_194_304}

    healthy = %{
      uptime_seconds: 273_600,
      memory: %{total: 298_844_160, processes: 121_634_816, ets: 18_874_368, binary: 41_943_040},
      process_count: 1432,
      process_limit: 262_144,
      run_queue: 0,
      schedulers: 8,
      host: host,
      db: db
    }

    [
      %Variation{id: :healthy, attributes: %{system_vitals: healthy}},
      %Variation{
        id: :run_queue_backed_up,
        attributes: %{system_vitals: %{healthy | run_queue: 14}}
      },
      %Variation{
        id: :processes_near_limit,
        attributes: %{system_vitals: %{healthy | process_count: 230_000}}
      }
    ]
  end
end
