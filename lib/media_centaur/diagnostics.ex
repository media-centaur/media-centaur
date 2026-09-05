defmodule MediaCentaur.Diagnostics do
  use Boundary,
    top_level?: true,
    deps: [MediaCentaur.Console, MediaCentaur.ErrorReports, MediaCentaur.Playback]

  @moduledoc """
  Structured diagnostic functions for production troubleshooting.

  Called via `bin/media_centaur rpc "MediaCentaur.Diagnostics.function()"`.
  Each function prints formatted output to stdout.
  """

  alias MediaCentaur.ErrorReports
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.Incident
  alias MediaCentaur.Playback.{SessionRegistry, Sessions}

  @doc "Supervision tree health and child counts."
  def status do
    children = Supervisor.which_children(MediaCentaur.Supervisor)
    running = Enum.count(children, fn {_, pid, _, _} -> is_pid(pid) end)
    total = length(children)
    IO.puts("#{running}/#{total} children running")
  end

  @doc "Prints the N most recent console buffer entries (default 20), oldest first."
  @spec log_recent(pos_integer()) :: :ok
  def log_recent(count \\ 20) when is_integer(count) and count > 0 do
    count
    |> MediaCentaur.Console.Buffer.recent()
    |> Enum.reverse()
    |> Enum.each(fn entry ->
      IO.puts(
        "#{DateTime.to_iso8601(entry.timestamp)} [#{entry.level}] #{entry.component}: #{entry.message}"
      )
    end)
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

  @doc "Watcher and pipeline state, media dirs, config."
  def services do
    watcher_children = length(Supervisor.which_children(MediaCentaur.Watcher.Supervisor))
    pipeline_children = length(Supervisor.which_children(MediaCentaur.Pipeline.Supervisor))

    IO.puts("Watcher children: #{watcher_children}")
    IO.puts("Pipeline children: #{pipeline_children}")

    media_dirs = MediaCentaur.Settings.Config.get(:media_dirs) || []
    IO.puts("Media dirs: #{inspect(media_dirs)}")

    registry_entries = SessionRegistry.list()
    IO.puts("Active sessions: #{length(registry_entries)}")
  end

  @doc """
  Lists recent durable incidents, most-recent activity first (default 20).

  The short id printed for each row is the handle `incident/1` accepts.
  """
  def incidents(limit \\ 20) do
    ErrorReports.list_incidents(limit: limit)
    |> format_incident_list()
    |> IO.puts()
  end

  @doc """
  Lists exactly the issues the Status page renders — the bucket cache
  (`ErrorReports.list_buckets/0`), grouped by subsystem. This is the faithful
  query for "what's on the board" (unlike `incidents/0`, which is the broader
  store listing). Each row's fingerprint is the handle `incident/1` and
  `dismiss/1` accept.
  """
  def issues do
    ErrorReports.list_buckets()
    |> format_issues()
    |> IO.puts()
  end

  @doc """
  Prints the full forensic dump for one incident — header plus its frozen
  context snapshot (lead-up logs, cross-subsystem vitals, the firing
  subsystem's contributor data, and triggering ids).

  `ref` is `:latest` (the default), a full incident id, a short id prefix (as
  printed by `incidents/0`), or a fingerprint.
  """
  def incident(ref \\ :latest) do
    ref = if ref in [:latest, "latest"], do: :latest, else: to_string(ref)

    case ErrorReports.find_incident(ref) do
      nil -> IO.puts("No incident found for #{inspect(ref)}")
      %Incident{} = incident -> IO.puts(format_incident(incident))
    end
  end

  @doc """
  Dismisses durable incidents — *removes* them (not `:resolved`), so they don't
  reappear on the next cache rebuild (`Buckets.dismiss/1` semantics). Use this to
  clear false-positives a fix has already addressed; a still-live fault mints a
  fresh incident from new evidence, so dismiss never permanently silences one.

  `ref` is:

    - `:all` — every issue currently on the board (the bulk "clear the board"),
      matching exactly what `issues/0` lists.
    - `:latest`, a full id, a short id prefix, or a fingerprint — a single one.
  """
  @spec dismiss(:all | :latest | String.t()) :: :ok
  def dismiss(:all) do
    case ErrorReports.list_buckets() do
      [] ->
        IO.puts("No issues on the board to dismiss")

      buckets ->
        ErrorReports.dismiss(Enum.map(buckets, & &1.fingerprint))
        IO.puts("Dismissed #{length(buckets)} issue(s) from the board")
    end
  end

  def dismiss(ref) do
    ref = if ref in [:latest, "latest"], do: :latest, else: to_string(ref)

    case ErrorReports.find_incident(ref) do
      nil ->
        IO.puts("No incident found for #{inspect(ref)}")

      %Incident{} = incident ->
        ErrorReports.dismiss([incident.fingerprint])
        IO.puts("Dismissed incident #{String.slice(incident.id, 0, 8)} — #{incident_title(incident)}")
    end
  end

  @doc "Renders the board-faithful issue listing, grouped by subsystem (pure)."
  @spec format_issues([Bucket.t()]) :: String.t()
  def format_issues([]), do: "No issues on the board"

  def format_issues(buckets) do
    groups = Enum.group_by(buckets, & &1.component)

    header =
      "Status issues (#{length(buckets)} across #{map_size(groups)} #{pluralize(map_size(groups), "subsystem")})\n"

    body =
      groups
      |> Enum.sort_by(fn {component, _} -> to_string(component) end)
      |> Enum.map_join("\n\n", &issue_group_section/1)

    footer =
      "\nDump one:  Diagnostics.incident(\"<fingerprint>\")\n" <>
        "Clear:     Diagnostics.dismiss(\"<fingerprint>\" | :all)"

    "#{header}\n#{body}\n#{footer}"
  end

  defp issue_group_section({component, buckets}) do
    worst = if Enum.any?(buckets, &(&1.severity in [:error, :critical])), do: "error", else: "warning"

    rows =
      buckets
      |> Enum.sort_by(&{severity_rank(&1.severity), -&1.count})
      |> Enum.map_join("\n", &issue_row/1)

    "#{component}  (#{length(buckets)} #{pluralize(length(buckets), "issue")}, worst: #{worst})\n#{rows}"
  end

  defp issue_row(%Bucket{} = bucket) do
    "  #{bucket.fingerprint}  #{String.pad_trailing(to_string(bucket.severity), 8)}×#{bucket.count}  #{String.slice(bucket.headline || "", 0, 90)}"
  end

  defp severity_rank(:critical), do: 0
  defp severity_rank(:error), do: 1
  defp severity_rank(:warning), do: 2
  defp severity_rank(_), do: 3

  defp pluralize(1, word), do: word
  defp pluralize(_, word), do: word <> "s"

  @doc "Renders a one-line-per-incident summary listing (pure)."
  @spec format_incident_list([Incident.t()]) :: String.t()
  def format_incident_list([]), do: "No incidents recorded"

  def format_incident_list(incidents) do
    Enum.map_join(incidents, "\n", &incident_summary_line/1)
  end

  @doc "Renders the full forensic dump for a single incident (pure)."
  @spec format_incident(Incident.t()) :: String.t()
  def format_incident(%Incident{} = incident) do
    [incident_header(incident), incident_context_section(incident)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp incident_summary_line(%Incident{} = incident) do
    "#{short_id(incident.id)}  [#{incident.severity}/#{incident.status}]  " <>
      "#{incident.component}  ×#{incident.count}  #{incident_title(incident)}  " <>
      "(#{format_timestamp(incident.last_seen)})"
  end

  defp incident_header(%Incident{} = incident) do
    lines = [
      "Incident #{short_id(incident.id)}  [#{incident.severity}/#{incident.status}]  #{incident.component}#{kind_suffix(incident.kind)}",
      "  Title:       #{incident_title(incident)}",
      "  Origin:      #{incident.origin}    Count: #{incident.count}",
      message_line(incident.message),
      description_line(incident.user_description),
      "  Fingerprint: #{incident.fingerprint}",
      "  First seen:  #{format_timestamp(incident.first_seen)}",
      "  Last seen:   #{format_timestamp(incident.last_seen)}",
      version_line(incident.app_version_at_first)
    ]

    lines |> Enum.reject(&(&1 == "")) |> Enum.join("\n")
  end

  defp incident_context_section(%Incident{} = incident) do
    case incident.latest_context || incident.first_context do
      context when is_map(context) and map_size(context) > 0 ->
        "\n  Frozen context:\n" <> format_context(context)

      _ ->
        "\n  No frozen context captured (snapshots populate on subsystem/user incidents)."
    end
  end

  defp format_context(context) do
    [
      context_kv("Triggering ids", Map.get(context, "triggering_ids")),
      context_kv("Crash reason", Map.get(context, "crash_reason")),
      vitals_block(Map.get(context, "vitals")),
      contributor_block(Map.get(context, "contributor")),
      lead_up_block(Map.get(context, "lead_up"))
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp context_kv(_label, value) when value in [nil, %{}], do: ""
  defp context_kv(label, value), do: "    #{label}: #{inspect(value)}"

  defp vitals_block(vitals) when is_map(vitals) and map_size(vitals) > 0 do
    body =
      Enum.map_join(vitals, "\n", fn {subsystem, data} -> "      #{subsystem}: #{inspect(data)}" end)

    "    Vitals:\n" <> body
  end

  defp vitals_block(_), do: ""

  defp contributor_block(contributor) when is_map(contributor) and map_size(contributor) > 0 do
    "    Contributor: #{inspect(contributor)}"
  end

  defp contributor_block(_), do: ""

  defp lead_up_block(lines) when is_list(lines) and lines != [] do
    body = Enum.map_join(lines, "\n", &lead_up_line/1)
    "    Lead-up (#{length(lines)} lines):\n" <> body
  end

  defp lead_up_block(_), do: ""

  defp lead_up_line(%{"message" => message} = line) do
    time = line |> Map.get("ts", "") |> time_of_iso8601()
    level = Map.get(line, "level", "?")
    component = Map.get(line, "component", "?")
    marker = if Map.get(line, "correlated"), do: "  (correlated)", else: ""
    "      [#{time}] [#{level}/#{component}] #{message}#{marker}"
  end

  defp lead_up_line(other), do: "      #{inspect(other)}"

  defp incident_title(%Incident{display_title: title}) when is_binary(title) and title != "", do: title
  defp incident_title(%Incident{component: component}), do: component

  defp message_line(message) when is_binary(message) and message != "", do: "  Message:     #{message}"
  defp message_line(_), do: ""

  defp description_line(description) when is_binary(description) and description != "",
    do: "  Reported:    #{description}"

  defp description_line(_), do: ""

  defp version_line(version) when is_binary(version) and version != "", do: "  Version:     #{version}"
  defp version_line(_), do: ""

  defp kind_suffix(kind) when is_binary(kind) and kind != "", do: "/#{kind}"
  defp kind_suffix(_), do: ""

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)
  defp short_id(_), do: "????????"

  defp format_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_timestamp(_), do: "unknown"

  defp time_of_iso8601(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> iso
    end
  end

  defp time_of_iso8601(_), do: "?"

  defp format_seconds(seconds) when is_number(seconds), do: MediaCentaur.Format.format_seconds(seconds)

  # Diagnostics shows "?" for an unknown/non-numeric duration rather than 0:00.
  defp format_seconds(_), do: "?"
end
