defmodule MediaCentaur.ErrorReports.ReportPayload do
  @moduledoc """
  Packages a bucket + environment into the `{title, body, labels}` an incident
  report is submitted as.

  Reuses the redacted markdown rendering from `IssueUrl` (title + body) but
  **without its URL size ladder** — the REST API body budget (~65 KB) is far
  larger than a `window.open` URL, so the full lead-up context ships untruncated.
  """
  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.IssueUrl
  alias MediaCentaur.ErrorReports.ReportTransport

  @labels ["incident", "auto-reported"]

  @spec build(Bucket.t(), EnvMetadata.t()) :: ReportTransport.payload()
  def build(%Bucket{} = bucket, %{} = env) do
    %{
      title: IssueUrl.format_title(bucket),
      body: IssueUrl.format_body(bucket, env, bucket.sample_entries),
      labels: @labels
    }
  end

  @doc """
  Packages a generic (un-anchored) user report from a current-state context
  snapshot plus the environment. Unlike `build/2`, there is no bucket to anchor
  to — the body is the normalized log lead-up and system vitals from the
  snapshot, so a user can file "something looks wrong" without a detected
  incident.
  """
  @spec build_generic(map(), EnvMetadata.t()) :: ReportTransport.payload()
  def build_generic(snapshot, %{} = env) when is_map(snapshot) do
    %{
      title: "User report — something looks wrong",
      body: generic_body(snapshot, env),
      labels: @labels
    }
  end

  defp generic_body(snapshot, env) do
    IO.iodata_to_binary([
      "## Environment\n",
      EnvMetadata.render(env),
      "\n\n## Recent log context (normalized)\n\n",
      format_lead_up(Map.get(snapshot, "lead_up", [])),
      "\n\n## System vitals\n\n```json\n",
      Jason.encode!(Map.get(snapshot, "vitals", %{}), pretty: true),
      "\n```\n",
      "\n---\nReported via Media Centaur's in-app error reporter (generic report).\n"
    ])
  end

  defp format_lead_up([]), do: "(no log context captured)\n"

  defp format_lead_up(lines) do
    Enum.map_join(lines, "\n", fn line ->
      "    #{line["ts"]} #{line["level"]} [#{line["component"]}] #{line["message"]}"
    end)
  end
end
