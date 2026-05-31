defmodule MediaCentaur.ErrorReports.ReportTransport do
  @moduledoc """
  Behaviour for delivering a packaged incident report off the machine.

  The default implementation (`GithubTransport`) files an issue in a private
  GitHub repo. The behaviour exists so the submission path is swappable and,
  crucially, **stubbable in tests** — no real network call ever runs in the
  suite. `ErrorReports.submit_report/2` picks the transport (configurable) and
  falls back to a copyable bundle when it returns an error.
  """
  @type payload :: %{title: String.t(), body: String.t(), labels: [String.t()]}
  @type result :: {:ok, url :: String.t()} | {:error, term()}

  @doc "Delivers `payload`. `opts` may carry transport-specific overrides."
  @callback submit(payload(), keyword()) :: result()
end
