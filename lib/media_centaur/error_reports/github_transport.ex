defmodule MediaCentaur.ErrorReports.GithubTransport do
  @moduledoc """
  `ReportTransport` that files an incident report as an issue in a **private**
  GitHub repo via the REST API — no user GitHub account, no `git`/SSH/`gh`.

  Authenticated by a fine-grained token scoped to `Issues:write` on that one
  repo, read from app config (`:diagnostics_report_token` /
  `:diagnostics_report_repo`, overridable per call). The token is opt-in: it is
  `nil` by default and only populated when an operator exports
  `MEDIA_CENTAUR_DIAGNOSTICS_REPORT_TOKEN` (wired in `config/runtime.exs`, so the
  secret stays out of the committed config and the user's plaintext TOML). With
  no token or repo configured (dev/showcase/unconfigured installs), it returns
  `{:error, :no_token}` / `{:error, :no_repo}` so the caller falls back to the
  copyable bundle — nothing leaves the machine without a configured inbox.

  > There is no mechanism that ships a token to end users, so a fresh install
  > does not auto-submit anywhere; the copy-paste fallback is the only path until
  > someone sets the env var. A centralized "every install reports to one inbox"
  > model would require embedding a shared token in the public release, which
  > carries Issues:write abuse risk — a deliberate decision, not yet made.

  The Req client is injectable (`opts[:client]`) so tests drive it through
  `Req.Test` and never touch the network.
  """
  @behaviour MediaCentaur.ErrorReports.ReportTransport

  alias MediaCentaur.Secret

  @base_url "https://api.github.com"

  @impl true
  def submit(payload, opts \\ []) do
    with {:ok, token} <- fetch_token(opts),
         {:ok, repo} <- fetch_repo(opts) do
      client = opts[:client] || default_client()
      post_issue(client, repo, payload, token)
    end
  end

  # Auth is applied per request (not baked into the client) so a test-injected
  # client still carries the Bearer token.
  defp post_issue(client, repo, payload, token) do
    body = %{
      title: payload.title,
      body: payload.body,
      labels: Map.get(payload, :labels, [])
    }

    case Req.post(client, url: "/repos/#{repo}/issues", json: body, auth: {:bearer, token}) do
      {:ok, %{status: 201, body: %{"html_url" => url}}} -> {:ok, url}
      {:ok, %{status: status, body: body}} -> {:error, {:http_error, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp default_client do
    Req.new(
      base_url: @base_url,
      headers: [
        {"accept", "application/vnd.github+json"},
        {"user-agent", "media-centaur"},
        {"x-github-api-version", "2022-11-28"}
      ]
    )
  end

  defp fetch_token(opts) do
    case opts[:token] || expose(Application.get_env(:media_centaur, :diagnostics_report_token)) do
      token when is_binary(token) and token != "" -> {:ok, token}
      _ -> {:error, :no_token}
    end
  end

  defp fetch_repo(opts) do
    case opts[:repo] || Application.get_env(:media_centaur, :diagnostics_report_repo) do
      repo when is_binary(repo) and repo != "" -> {:ok, repo}
      _ -> {:error, :no_repo}
    end
  end

  # The token may be wrapped in a Secret (to keep it out of inspect/logs) or be
  # a plain string from app config.
  defp expose(%Secret{} = secret), do: Secret.expose(secret)
  defp expose(other), do: other
end
