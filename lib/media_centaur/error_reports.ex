defmodule MediaCentaur.ErrorReports do
  use Boundary,
    deps: [MediaCentaur.Console],
    exports: [
      Bucket,
      DiagnosticEvent,
      EnvMetadata,
      Fingerprint,
      Incident,
      IncidentContext,
      IssueUrl,
      Redactor,
      ReportPayload
    ]

  @moduledoc """
  Bounded context for error report aggregation and GitHub issue submission.

  Subscribes to the Console log stream, groups `:error`-level entries by a
  normalized-message fingerprint, and exposes a 1-hour rolling snapshot.
  Submission is browser-side: `IssueUrl.build/2` produces a GitHub
  new-issue URL that the status page opens via `window.open`.
  """

  alias MediaCentaur.ErrorReports.Buckets
  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.GithubTransport
  alias MediaCentaur.ErrorReports.ReportPayload
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Topics

  @spec list_buckets() :: [__MODULE__.Bucket.t()]
  defdelegate list_buckets(), to: Buckets

  @spec get_bucket(binary()) :: __MODULE__.Bucket.t() | nil
  defdelegate get_bucket(fingerprint), to: Buckets

  @doc "Overall diagnostics health rollup — see `Store.health/0`."
  @spec health() :: Store.health_rollup()
  defdelegate health(), to: Store

  @doc """
  Raises (or re-asserts) a `:subsystem` fault grouped by `{component, kind}`.

  The instant-the-fault-happens entry point a subsystem calls directly; the
  periodic evaluator uses the same path. `opts`: `:occurred_at` (default now),
  `:message`, `:display_title`.
  """
  @spec raise_fault(atom(), atom(), atom(), keyword()) ::
          {:ok, __MODULE__.Incident.t()} | {:error, Ecto.Changeset.t()}
  def raise_fault(component, kind, severity, opts \\ []) do
    Store.raise_fault(%{
      component: component,
      kind: kind,
      severity: severity,
      occurred_at: opts[:occurred_at] || DateTime.utc_now(),
      message: opts[:message],
      display_title: opts[:display_title]
    })
  end

  @doc "Resolves the open `:subsystem` fault for `{component, kind}` (no-op if none open)."
  @spec resolve_fault(atom(), atom(), keyword()) ::
          {:ok, __MODULE__.Incident.t()} | {:ok, :none} | {:error, Ecto.Changeset.t()}
  def resolve_fault(component, kind, opts \\ []) do
    Store.resolve_fault(component, kind, opts[:resolved_at] || DateTime.utc_now())
  end

  @doc """
  Packages `bucket` into an incident report and submits it via the configured
  `ReportTransport`.

  Returns `{:ok, url}` on success. On any failure — no token configured
  (dev/showcase), network error, or a non-201 response — returns
  `{:fallback, bundle}` where `bundle` is the redacted report text for the user
  to copy, so a report is never lost. `opts[:transport]` overrides the transport
  (for tests); other opts pass through to it.
  """
  @spec submit_report(__MODULE__.Bucket.t(), keyword()) :: {:ok, String.t()} | {:fallback, String.t()}
  def submit_report(bucket, opts \\ []) do
    payload = ReportPayload.build(bucket, EnvMetadata.collect())
    transport = opts[:transport] || configured_transport()

    case transport.submit(payload, opts) do
      {:ok, url} -> {:ok, url}
      {:error, _reason} -> {:fallback, payload.title <> "\n\n" <> payload.body}
    end
  end

  defp configured_transport do
    Application.get_env(:media_centaur, :diagnostics_transport, GithubTransport)
  end

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.error_reports())
end
