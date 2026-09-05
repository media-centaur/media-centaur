defmodule MediaCentaur.ErrorReports.IssueUrlTest do
  # `async: false` — one test writes application env (a shared value).
  use ExUnit.Case, async: false

  alias MediaCentaur.ErrorReports.{Bucket, IssueUrl}

  defp sample_bucket(overrides \\ %{}) do
    bucket = %Bucket{
      fingerprint: "3f9c1a2b4e5d6f70",
      component: :tmdb,
      normalized_message: "TMDB returned <N>: rate limited (retry after <N>s)",
      display_title: "[TMDB] TMDB returned <N>: rate limited (retry after <N>s)",
      severity: :error,
      count: 12,
      first_seen: ~U[2026-04-24 13:48:02Z],
      last_seen: ~U[2026-04-24 14:00:19Z],
      sample_entries: []
    }

    then(Map.merge(bucket, overrides), &struct!(Bucket, Map.from_struct(&1)))
  end

  defp sample_env do
    %{
      app_version: "0.21.0",
      otp_release: "27",
      elixir_version: "1.17.0",
      os: "Linux 6.19.12-arch1-1 (x86_64)",
      locale: "en_US.UTF-8",
      uptime: "2h 14m"
    }
  end

  describe "format_body/3" do
    test "renders environment, fingerprint, and recurrence counts" do
      body = IssueUrl.format_body(sample_bucket(), sample_env(), [])
      assert body =~ "0.21.0"
      assert body =~ "Fingerprint: 3f9c1a2b4e5d6f70"
      assert body =~ "Count:"
      assert body =~ "12"
      assert body =~ "First seen:"
    end

    test "includes the redacted log sample lines" do
      entries = [%{timestamp: ~U[2026-04-24 14:00:00Z], message: "no such file <path>"}]
      body = IssueUrl.format_body(sample_bucket(), sample_env(), entries)
      assert body =~ "no such file <path>"
    end
  end

  describe "format_title/1" do
    test "uses the bucket display_title verbatim, truncated to 140 chars" do
      long_title = "[TMDB] " <> String.duplicate("x", 500)
      bucket = sample_bucket(%{display_title: long_title})
      assert String.length(IssueUrl.format_title(bucket)) <= 140
    end
  end

  describe "new_issue_url/3" do
    test "targets the configured public repo and prefills the title + body + labels" do
      url =
        IssueUrl.new_issue_url(
          "Boom happened",
          "## Environment\nthings broke",
          ["incident", "auto-reported"]
        )

      assert url =~ "https://github.com/media-centaur/media-centaur/issues/new?"
      assert url =~ "title=Boom+happened"
      assert url =~ "labels=incident%2Cauto-reported"
      # The actual body is embedded in the URL, not just a paste placeholder.
      assert url =~ "body=%23%23+Environment"
      refute url =~ "clipboard"
    end

    test "percent-encodes special characters in the title" do
      url = IssueUrl.new_issue_url("crash: a/b #4 — é", "body", [])
      assert url =~ "title=crash%3A+a%2Fb+%234+%E2%80%94+%C3%A9"
      refute url =~ "labels="
    end

    test "falls back to the clipboard paste placeholder when the body is too long for a URL" do
      url = IssueUrl.new_issue_url("Boom", String.duplicate("x", 10_000), [])

      assert url =~ "clipboard"
      refute url =~ "xxxxxxxxxx"
      assert byte_size(url) < 9_000
    end

    test "honors a :diagnostics_issues_repo override" do
      original = Application.get_env(:media_centaur, :diagnostics_issues_repo)
      Application.put_env(:media_centaur, :diagnostics_issues_repo, "acme/widgets")
      on_exit(fn -> Application.put_env(:media_centaur, :diagnostics_issues_repo, original) end)

      assert IssueUrl.new_issue_url("x", "body", []) =~ "https://github.com/acme/widgets/issues/new?"
    end
  end
end
