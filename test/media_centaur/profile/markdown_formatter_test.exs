defmodule MediaCentaur.Profile.MarkdownFormatterTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Profile.{MarkdownFormatter, RunData}

  defp run do
    %RunData{
      schema_version: RunData.schema_version(),
      metadata: %{
        run_id: "run-42",
        timestamp: "2026-06-15T00:00:00Z",
        scale: "small",
        git_sha: "abc1234",
        git_branch: "main",
        dirty: false,
        otp_release: "27",
        elixir_version: "1.19.0",
        schedulers_online: 8,
        cpu_count: 8,
        database_path: "/tmp/test.db"
      },
      microbenchmarks: [],
      page_mounts: [],
      ets_memory: [],
      deltas: nil
    }
  end

  describe "render!/1" do
    test "renders the report heading and run metadata" do
      output = MarkdownFormatter.render!(run())

      assert is_binary(output)
      assert output =~ "# Media Centaur Profile Run"
      assert output =~ "run-42"
      assert output =~ "abc1234"
    end
  end
end
