defmodule MediaCentaur.ErrorReports.GithubTransportTest do
  use ExUnit.Case, async: false

  alias MediaCentaur.ErrorReports.GithubTransport

  defp client, do: Req.new(plug: {Req.Test, :gh_reports}, retry: false)
  defp payload, do: %{title: "Incident", body: "the body", labels: ["incident"]}

  defp json(conn, status, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(data))
  end

  test "files an issue and returns the html_url on 201" do
    Req.Test.stub(:gh_reports, fn conn ->
      assert conn.request_path == "/repos/owner/reports/issues"
      assert {"authorization", "Bearer tok123"} in conn.req_headers
      json(conn, 201, %{"html_url" => "https://github.com/owner/reports/issues/7"})
    end)

    assert {:ok, "https://github.com/owner/reports/issues/7"} =
             GithubTransport.submit(payload(), client: client(), token: "tok123", repo: "owner/reports")
  end

  test "returns :no_token when no token is configured" do
    assert {:error, :no_token} = GithubTransport.submit(payload(), repo: "owner/reports")
  end

  test "returns :no_repo when a token but no repo is configured" do
    # config.exs ships a default repo; clear it to exercise the no-repo path
    # (and so this test never reaches the network).
    original = Application.get_env(:media_centaur, :diagnostics_report_repo)
    Application.put_env(:media_centaur, :diagnostics_report_repo, nil)
    on_exit(fn -> Application.put_env(:media_centaur, :diagnostics_report_repo, original) end)

    assert {:error, :no_repo} = GithubTransport.submit(payload(), token: "tok123")
  end

  test "surfaces a non-201 response as an http_error" do
    Req.Test.stub(:gh_reports, fn conn -> json(conn, 401, %{"message" => "Bad credentials"}) end)

    assert {:error, {:http_error, 401, %{"message" => "Bad credentials"}}} =
             GithubTransport.submit(payload(), client: client(), token: "bad", repo: "owner/reports")
  end
end
