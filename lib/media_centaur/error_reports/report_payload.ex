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
      body: IssueUrl.format_body(bucket, env, bucket.sample_entries, []),
      labels: @labels
    }
  end
end
