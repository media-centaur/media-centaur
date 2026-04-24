defmodule MediaCentarr.ErrorReports.IssueUrl do
  @moduledoc """
  Builds a GitHub `new/issue` URL for an `ErrorReports.Bucket`.

  All submission is browser-side: the URL is handed to `window.open`.
  Size-budgeting is load-bearing — browsers typically accept up to about
  8 KB of URL. This module targets ≤ 7,500 bytes and, when over budget,
  drops content in priority order:

  1. Log context lines → `:truncated_log_context`
  2. Recurrences detail (first/last seen timestamps) → `:truncated_recurrences`
  3. Normalized message → `:truncated_message`

  Environment block and fingerprint are always preserved.
  """

  alias MediaCentarr.ErrorReports.{Bucket, EnvMetadata}

  @repo_url "https://github.com/media-centarr/media-centarr"
  @max_url_bytes 7_500
  @title_limit 140

  @type flag :: :truncated_log_context | :truncated_recurrences | :truncated_message
  @type build_result :: {:ok, binary(), [flag()]}

  @spec build(Bucket.t(), EnvMetadata.t()) :: build_result()
  def build(%Bucket{} = bucket, %{} = env) do
    title = format_title(bucket)
    build_with_log_truncation(bucket, env, title, length(bucket.sample_entries), [])
  end

  @spec format_title(Bucket.t()) :: binary()
  def format_title(%Bucket{display_title: title}) do
    String.slice(title, 0, @title_limit)
  end

  # Stage 1: drop log context lines one at a time (oldest first) until fit.
  defp build_with_log_truncation(bucket, env, title, log_limit, flags) do
    sample = Enum.take(bucket.sample_entries, log_limit)
    body = format_body(bucket, env, sample, flags)
    url = encode_url(title, body)

    cond do
      byte_size(url) <= @max_url_bytes ->
        {:ok, url, flags}

      log_limit > 0 ->
        new_flags =
          if :truncated_log_context in flags, do: flags, else: [:truncated_log_context | flags]

        build_with_log_truncation(bucket, env, title, log_limit - 1, new_flags)

      true ->
        # Log context fully dropped — move to stage 2.
        build_with_recurrence_truncation(bucket, env, title, flags)
    end
  end

  # Stage 2: drop first/last seen timestamps from the recurrences block.
  defp build_with_recurrence_truncation(bucket, env, title, flags) do
    new_flags = [:truncated_recurrences | flags]
    body = format_body(bucket, env, [], new_flags)
    url = encode_url(title, body)

    if byte_size(url) <= @max_url_bytes do
      {:ok, url, new_flags}
    else
      build_with_message_truncation(bucket, env, title, new_flags, url)
    end
  end

  # Stage 3: truncate normalized_message to fit the remaining budget.
  defp build_with_message_truncation(bucket, env, title, flags, current_url) do
    overage = byte_size(current_url) - @max_url_bytes
    current_msg_bytes = byte_size(bucket.normalized_message)
    # Subtract overage + 100-byte cushion for URL encoding overhead.
    new_msg_limit = max(0, current_msg_bytes - overage - 100)
    truncated_msg = binary_part(bucket.normalized_message, 0, new_msg_limit)
    truncated_bucket = %{bucket | normalized_message: truncated_msg}
    new_flags = [:truncated_message | flags]

    body = format_body(truncated_bucket, env, [], new_flags)
    url = encode_url(title, body)

    if byte_size(url) <= @max_url_bytes do
      {:ok, url, new_flags}
    else
      # One more iteration with the actual overage from the truncated version.
      overage2 = byte_size(url) - @max_url_bytes
      new_msg_limit2 = max(0, new_msg_limit - overage2 - 100)
      truncated_msg2 = binary_part(bucket.normalized_message, 0, new_msg_limit2)
      truncated_bucket2 = %{bucket | normalized_message: truncated_msg2}
      body2 = format_body(truncated_bucket2, env, [], new_flags)
      url2 = encode_url(title, body2)
      # Best-effort: return even if still marginally over (env block is enormous).
      {:ok, url2, new_flags}
    end
  end

  @spec format_body(Bucket.t(), EnvMetadata.t(), [Bucket.sample_entry()], [flag()]) :: binary()
  def format_body(%Bucket{} = bucket, %{} = env, sample_entries, flags) do
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
      recurrences_block(bucket, flags),
      "\nNormalized message:\n\n",
      indent(bucket.normalized_message),
      "\n\n## Recent log context (normalized)\n\n",
      format_samples(sample_entries),
      "\n\n---\nReported via Media Centarr's in-app error reporter.\n"
    ])
  end

  defp recurrences_block(bucket, flags) do
    if :truncated_recurrences in flags do
      ["Count:       ", Integer.to_string(bucket.count), " (in the last window)\n"]
    else
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

  defp encode_url(title, body) do
    qs = URI.encode_query(%{"title" => title, "body" => body})
    @repo_url <> "/issues/new?" <> qs
  end
end
