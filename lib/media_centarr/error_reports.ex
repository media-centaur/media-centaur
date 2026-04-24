defmodule MediaCentarr.ErrorReports do
  use Boundary,
    deps: [MediaCentarr.Console],
    exports: [Bucket, EnvMetadata, Fingerprint, IssueUrl, Redactor]

  @moduledoc """
  Bounded context for error report aggregation and GitHub issue submission.

  Subscribes to the Console log stream, groups `:error`-level entries by a
  normalized-message fingerprint, and exposes a 1-hour rolling snapshot.
  Submission is browser-side: `IssueUrl.build/2` produces a GitHub
  new-issue URL that the status page opens via `window.open`.
  """

  alias MediaCentarr.ErrorReports.Buckets
  alias MediaCentarr.Topics

  @spec list_buckets() :: [__MODULE__.Bucket.t()]
  defdelegate list_buckets(), to: Buckets

  @spec get_bucket(binary()) :: __MODULE__.Bucket.t() | nil
  defdelegate get_bucket(fingerprint), to: Buckets

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.error_reports())
end
