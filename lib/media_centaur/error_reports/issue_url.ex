defmodule MediaCentaur.ErrorReports.IssueUrl do
  @moduledoc """
  Renders the redacted Markdown (title + body) for an incident report.

  Despite the legacy name, this **no longer builds a URL** — submission moved to
  `ReportPayload` + `GithubTransport` (private-repo REST, observability Phase 3).
  `format_title/1` and `format_body/3` remain the single source of the report's
  human-readable Markdown, reused by `ReportPayload.build/2`. (Candidate to fold
  into `ReportPayload` and retire this module name.)
  """

  alias MediaCentaur.ErrorReports.{Bucket, EnvMetadata}

  @title_limit 140

  @spec format_title(Bucket.t()) :: binary()
  def format_title(%Bucket{display_title: title}) do
    String.slice(title, 0, @title_limit)
  end

  @spec format_body(Bucket.t(), EnvMetadata.t(), [Bucket.sample_entry()]) :: binary()
  def format_body(%Bucket{} = bucket, %{} = env, sample_entries) do
    IO.iodata_to_binary([
      "## Environment\n",
      EnvMetadata.render(env),
      "\n\n",
      "## Error\n",
      "Fingerprint: ",
      bucket.fingerprint,
      "\n",
      "Component:   ",
      Atom.to_string(bucket.component),
      "\n",
      recurrences_block(bucket),
      "\nNormalized message:\n\n",
      indent(bucket.normalized_message),
      "\n\n## Recent log context (normalized)\n\n",
      format_samples(sample_entries),
      "\n\n---\nReported via Media Centaur's in-app error reporter.\n"
    ])
  end

  defp recurrences_block(bucket) do
    [
      "Count:       ",
      Integer.to_string(bucket.count),
      " (in the last window)\n",
      "First seen:  ",
      DateTime.to_iso8601(bucket.first_seen),
      "\n",
      "Last seen:   ",
      DateTime.to_iso8601(bucket.last_seen),
      "\n"
    ]
  end

  defp format_samples([]), do: "(no log context included)\n"

  defp format_samples(entries) do
    Enum.map_join(entries, "\n", fn entry ->
      ts =
        entry.timestamp
        |> DateTime.to_time()
        |> Time.to_string()
        |> String.slice(0, 8)

      "    #{ts} error " <> entry.message
    end)
  end

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end
end
