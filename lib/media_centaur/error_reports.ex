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
  Submission is server-side: `ReportPayload` formats the issue body, and
  `GithubTransport` posts it to a private GitHub repo via the REST API
  (`submit_payload/2`). When no token is configured or the request fails,
  the caller receives a `{:fallback, bundle}` with the redacted text for
  the user to copy. `IssueUrl` is an internal Markdown formatter reused by
  `ReportPayload` — it no longer drives browser-side submission.
  """

  alias MediaCentaur.ErrorReports.Buckets
  alias MediaCentaur.ErrorReports.ContextSnapshot
  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.GithubTransport
  alias MediaCentaur.ErrorReports.ReportPayload
  alias MediaCentaur.ErrorReports.ReportTransport
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Topics

  @spec list_buckets() :: [__MODULE__.Bucket.t()]
  defdelegate list_buckets(), to: Buckets

  @spec get_bucket(binary()) :: __MODULE__.Bucket.t() | nil
  defdelegate get_bucket(fingerprint), to: Buckets

  @doc "Overall diagnostics health rollup — see `Store.health/0`."
  @spec health() :: Store.health_rollup()
  defdelegate health(), to: Store

  @doc "Creates an ungrouped open `:user` incident — see `Store.create_user_incident/1`."
  @spec create_user_incident(map()) :: {:ok, __MODULE__.Incident.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_user_incident(attrs), to: Store

  @doc "Counts open auto-detected incidents newer than `since` — see `Store.count_unseen_incidents/1`."
  @spec count_unseen_incidents(DateTime.t()) :: non_neg_integer()
  defdelegate count_unseen_incidents(since), to: Store

  @doc "Lists incidents most-recent first — see `Store.list_incidents/1`."
  @spec list_incidents(keyword()) :: [__MODULE__.Incident.t()]
  defdelegate list_incidents(opts \\ []), to: Store

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
    bucket
    |> ReportPayload.build(EnvMetadata.collect())
    |> submit_payload(opts)
  end

  @doc """
  Submits an already-built (possibly user-edited) payload via the configured
  transport. `{:ok, url}` on success; `{:fallback, bundle}` (the payload's own
  title + body, for the user to copy) on any transport error.
  """
  @spec submit_payload(map(), keyword()) :: {:ok, String.t()} | {:fallback, String.t()}
  def submit_payload(payload, opts \\ []) do
    transport = opts[:transport] || configured_transport()

    case transport.submit(payload, opts) do
      {:ok, url} -> {:ok, url}
      {:error, _reason} -> {:fallback, payload.title <> "\n\n" <> payload.body}
    end
  end

  @doc """
  Assembles the final report body: the user's narrative (if any) as a leading
  section, then the (possibly edited) technical body.
  """
  @spec assemble_body(String.t(), String.t()) :: String.t()
  def assemble_body(narrative, technical_body) do
    case String.trim(narrative || "") do
      "" -> technical_body
      text -> "## What happened (in the user's words)\n\n" <> text <> "\n\n" <> technical_body
    end
  end

  @doc """
  Assembles a generic (un-anchored) user report: a current-state context snapshot
  plus the `%{title, body, labels}` payload to seed the consent modal. The caller
  keeps `snapshot` to persist on submit via `create_user_report/2`.
  """
  @spec build_generic_report() :: %{snapshot: map(), payload: ReportTransport.payload()}
  def build_generic_report do
    snapshot = ContextSnapshot.assemble(:user, %{})
    %{snapshot: snapshot, payload: ReportPayload.build_generic(snapshot, EnvMetadata.collect())}
  end

  @doc """
  Persists the `:user` incident (best-effort — submission is not blocked if the
  local write fails) and submits the (already edited + assembled) payload.
  """
  @spec create_user_report(map(), keyword()) :: {:ok, String.t()} | {:fallback, String.t()}
  def create_user_report(%{user_description: desc, snapshot: snapshot, payload: payload}, opts \\ []) do
    _ = create_user_incident(%{user_description: desc, first_context: snapshot})
    submit_payload(payload, opts)
  end

  defp configured_transport do
    Application.get_env(:media_centaur, :diagnostics_transport, GithubTransport)
  end

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.error_reports())
end
