defmodule MediaCentaur.ErrorReports.IssueUrl do
  @moduledoc """
  Renders the redacted Markdown for an incident report and builds the prefilled GitHub new-issue URL.

  `format_title/1` and `format_body/3` produce the human-readable Markdown reused by
  `ReportPayload.build/2`. `new_issue_url/3` builds the prefilled public GitHub
  new-issue URL (title + body) for user-submitted reports.
  """

  alias MediaCentaur.ErrorReports.{Bucket, EnvMetadata}

  @title_limit 140
  @default_repo "media-centaur/media-centaur"
  @paste_placeholder "<!-- Paste your report below — it's on your clipboard (Ctrl/Cmd+V). -->\n\n"

  # GitHub rejects very long prefill URLs (and browsers/proxies cap URL length).
  # Under this budget we embed the full report body so the issue description is
  # genuinely prefilled; over it we fall back to the clipboard paste prompt.
  @max_url_bytes 8_000

  @spec format_title(Bucket.t()) :: binary()
  def format_title(%Bucket{display_title: title}) do
    String.slice(title, 0, @title_limit)
  end

  @doc """
  Builds the prefilled public GitHub new-issue URL with the title and the
  reviewed/redacted report body baked into the issue description. If the body
  pushes the URL past `@max_url_bytes`, it degrades to the clipboard paste prompt
  (the body still rides the clipboard). `labels` are best-effort (GitHub drops
  `labels=` for reporters without triage rights).
  """
  @spec new_issue_url(binary(), binary(), [binary()]) :: binary()
  def new_issue_url(title, body, labels \\ []) do
    url = build_url(title, body, labels)

    if byte_size(url) <= @max_url_bytes,
      do: url,
      else: build_url(title, @paste_placeholder, labels)
  end

  defp build_url(title, body, labels) do
    repo = Application.get_env(:media_centaur, :diagnostics_issues_repo, @default_repo)

    params =
      then(%{"title" => title, "body" => body}, fn p ->
        if labels == [], do: p, else: Map.put(p, "labels", Enum.join(labels, ","))
      end)

    "https://github.com/#{repo}/issues/new?" <> URI.encode_query(params)
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
