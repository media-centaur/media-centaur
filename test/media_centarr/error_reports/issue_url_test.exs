defmodule MediaCentarr.ErrorReports.IssueUrlTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ErrorReports.{Bucket, IssueUrl}

  defp sample_bucket(overrides \\ %{}) do
    bucket = %Bucket{
      fingerprint: "3f9c1a2b4e5d6f70",
      component: :tmdb,
      normalized_message: "TMDB returned <N>: rate limited (retry after <N>s)",
      display_title: "[TMDB] TMDB returned <N>: rate limited (retry after <N>s)",
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

  describe "build/2" do
    test "returns a valid github new-issue URL" do
      {:ok, url, flags} = IssueUrl.build(sample_bucket(), sample_env())
      parsed = URI.parse(url)
      assert parsed.host == "github.com"
      assert parsed.path == "/media-centarr/media-centarr/issues/new"
      assert is_list(flags)
    end

    test "title encodes the display title" do
      {:ok, url, _} = IssueUrl.build(sample_bucket(), sample_env())
      query = URI.decode_query(URI.parse(url).query)
      assert query["title"] =~ "[TMDB]"
      assert query["title"] =~ "rate limited"
    end

    test "body contains environment + fingerprint + counts" do
      {:ok, url, _} = IssueUrl.build(sample_bucket(), sample_env())
      body = URI.parse(url).query |> URI.decode_query() |> Map.get("body")
      assert body =~ "0.21.0"
      assert body =~ "Fingerprint: 3f9c1a2b4e5d6f70"
      assert body =~ "Count:"
      assert body =~ "12"
    end

    test "drops log-context lines when too long; returns :truncated_log_context flag" do
      many_entries =
        for i <- 1..500 do
          %{
            timestamp: ~U[2026-04-24 14:00:00Z],
            message: "error line #{i} " <> String.duplicate("x", 50)
          }
        end

      bucket = sample_bucket(%{sample_entries: many_entries})
      {:ok, url, flags} = IssueUrl.build(bucket, sample_env())
      assert :truncated_log_context in flags
      assert byte_size(url) <= 7_500
    end

    test "always preserves environment + fingerprint even under extreme pressure" do
      # 100 KB bucket message
      huge = String.duplicate("x", 100_000)
      bucket = sample_bucket(%{normalized_message: huge, display_title: "[TMDB] " <> huge})
      {:ok, url, _flags} = IssueUrl.build(bucket, sample_env())
      body = URI.parse(url).query |> URI.decode_query() |> Map.get("body")
      assert body =~ "0.21.0"
      assert body =~ "Fingerprint:"
      assert byte_size(url) <= 7_500
    end
  end

  describe "format_title/1" do
    test "uses the bucket display_title verbatim, truncated to 140 chars" do
      long_title = "[TMDB] " <> String.duplicate("x", 500)
      bucket = sample_bucket(%{display_title: long_title})
      assert String.length(IssueUrl.format_title(bucket)) <= 140
    end
  end
end
