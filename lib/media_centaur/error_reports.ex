defmodule MediaCentaur.ErrorReports do
  use Boundary,
    deps: [MediaCentaur.Console, MediaCentaur.Retention],
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
  Submission is browser-side: `ReportPayload` formats the issue body, and
  `finalize_report/1` returns the redacted text plus a prefilled public
  new-issue URL (`IssueUrl.new_issue_url/3`). The user posts the issue under
  their own GitHub login — there is no network call in the submission path.
  """

  alias MediaCentaur.ErrorReports.Buckets
  alias MediaCentaur.ErrorReports.ContextSnapshot
  alias MediaCentaur.ErrorReports.EnvMetadata
  alias MediaCentaur.ErrorReports.IssueUrl
  alias MediaCentaur.ErrorReports.ReportPayload
  alias MediaCentaur.ErrorReports.Store
  alias MediaCentaur.Topics

  @spec list_buckets() :: [__MODULE__.Bucket.t()]
  defdelegate list_buckets(), to: Buckets

  @spec get_bucket(binary()) :: __MODULE__.Bucket.t() | nil
  defdelegate get_bucket(fingerprint), to: Buckets

  @doc "Dismisses the issues behind the given fingerprints — see `Buckets.dismiss/2`."
  @spec dismiss([binary()]) :: :ok
  defdelegate dismiss(fingerprints), to: Buckets

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

  @doc "Resolves an incident by `:latest`, full id, id-prefix, or fingerprint — see `Store.find_incident/1`."
  @spec find_incident(:latest | String.t()) :: __MODULE__.Incident.t() | nil
  defdelegate find_incident(ref), to: Store

  @doc """
  Raises (or re-asserts) a `:subsystem` fault grouped by `{component, kind}`.

  The instant-the-fault-happens entry point a subsystem calls directly; the
  periodic evaluator uses the same path. `opts`: `:occurred_at` (default now),
  `:message`, `:display_title`.
  """
  @spec raise_fault(atom(), atom(), atom(), keyword()) ::
          {:ok, __MODULE__.Incident.t()} | {:error, Ecto.Changeset.t()}
  def raise_fault(component, kind, severity, opts \\ []) do
    with {:ok, incident} <-
           Store.raise_fault(%{
             component: component,
             kind: kind,
             severity: severity,
             occurred_at: opts[:occurred_at] || DateTime.utc_now(),
             message: opts[:message],
             display_title: opts[:display_title]
           }) do
      Buckets.fault_raised(incident)
      {:ok, incident}
    end
  end

  @doc "Resolves the open `:subsystem` fault for `{component, kind}` (no-op if none open)."
  @spec resolve_fault(atom(), atom(), keyword()) ::
          {:ok, __MODULE__.Incident.t()} | {:ok, :none} | {:error, Ecto.Changeset.t()}
  def resolve_fault(component, kind, opts \\ []) do
    with {:ok, %__MODULE__.Incident{} = incident} <-
           Store.resolve_fault(component, kind, opts[:resolved_at] || DateTime.utc_now()) do
      Buckets.fault_resolved(Store.fault_fingerprint(component, kind))
      {:ok, incident}
    end
  end

  @doc """
  Finalizes a (possibly user-edited) payload for browser-side posting: returns the
  title, body, and the prefilled public GitHub new-issue URL. No network call.
  """
  @spec finalize_report(ReportPayload.payload()) ::
          %{title: String.t(), body: String.t(), issue_url: String.t()}
  def finalize_report(%{title: title, body: body} = payload) do
    %{
      title: title,
      body: body,
      issue_url: IssueUrl.new_issue_url(title, body, Map.get(payload, :labels, []))
    }
  end

  @doc """
  Best-effort persistence of the `:user` incident (submission is never blocked by a
  local write failure).
  """
  @spec persist_user_incident(map()) :: :ok
  def persist_user_incident(%{user_description: description, snapshot: snapshot}) do
    _ = create_user_incident(%{user_description: description, first_context: snapshot})
    :ok
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
  keeps `snapshot` to persist on submit via `persist_user_incident/1`.
  """
  @spec build_generic_report() :: %{snapshot: map(), payload: ReportPayload.payload()}
  def build_generic_report do
    snapshot = ContextSnapshot.assemble(:user, %{})
    %{snapshot: snapshot, payload: ReportPayload.build_generic(snapshot, EnvMetadata.collect())}
  end

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.error_reports())
end
