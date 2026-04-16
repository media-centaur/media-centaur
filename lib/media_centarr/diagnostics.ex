defmodule MediaCentarr.Diagnostics do
  @moduledoc """
  Structured diagnostic functions for production troubleshooting.

  Called via `bin/media_centarr rpc "MediaCentarr.Diagnostics.function()"`.
  Each function prints formatted output to stdout.
  """

  alias MediaCentarr.Playback.{SessionRegistry, Sessions}

  @doc "Supervision tree health and child counts."
  def status do
    children = Supervisor.which_children(MediaCentarr.Supervisor)
    running = Enum.count(children, fn {_, pid, _, _} -> is_pid(pid) end)
    total = length(children)
    IO.puts("#{running}/#{total} children running")
  end

  @doc "Active playback sessions and their state."
  def playback do
    sessions = Sessions.list()

    if sessions == [] do
      IO.puts("No active sessions")
    else
      for session <- sessions do
        state = session[:state] || :unknown
        name = get_in(session, [:now_playing, :entity_name]) || session.entity_id
        IO.puts("  #{state} — #{name}")

        if now_playing = session[:now_playing] do
          if now_playing[:season_number] do
            IO.puts(
              "    S#{now_playing.season_number}E#{now_playing.episode_number} #{now_playing[:episode_name] || ""}"
            )
          end

          if now_playing[:position_seconds] && now_playing[:duration_seconds] do
            IO.puts(
              "    #{format_seconds(now_playing.position_seconds)} / #{format_seconds(now_playing.duration_seconds)}"
            )
          end
        end
      end
    end
  end

  @doc "Recent console log entries (newest first)."
  def log_recent(count \\ 20) do
    entries = MediaCentarr.Console.recent_entries(count)

    if entries == [] do
      IO.puts("No log entries in buffer")
    else
      for entry <- Enum.reverse(entries) do
        ts = Calendar.strftime(entry.timestamp, "%H:%M:%S")
        component = entry.component || :system
        IO.puts("[#{ts}] [#{entry.level}] [#{component}] #{entry.message}")
      end
    end
  end

  @doc "Watcher and pipeline state, watch dirs, config."
  def services do
    watcher_children = Supervisor.which_children(MediaCentarr.Watcher.Supervisor) |> length()
    pipeline_children = Supervisor.which_children(MediaCentarr.Pipeline.Supervisor) |> length()

    IO.puts("Watcher children: #{watcher_children}")
    IO.puts("Pipeline children: #{pipeline_children}")

    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []
    IO.puts("Watch dirs: #{inspect(watch_dirs)}")

    registry_entries = SessionRegistry.list()
    IO.puts("Active sessions: #{length(registry_entries)}")
  end

  defp format_seconds(seconds) when is_number(seconds) do
    total = round(seconds)
    h = div(total, 3600)
    m = div(rem(total, 3600), 60)
    s = rem(total, 60)

    if h > 0 do
      "#{h}:#{String.pad_leading("#{m}", 2, "0")}:#{String.pad_leading("#{s}", 2, "0")}"
    else
      "#{m}:#{String.pad_leading("#{s}", 2, "0")}"
    end
  end

  defp format_seconds(_), do: "?"
end
