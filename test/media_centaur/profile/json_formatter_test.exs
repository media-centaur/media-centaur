defmodule MediaCentaur.Profile.JSONFormatterTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Profile.{JSONFormatter, RunData}

  # A RunData already in the serialised (jsonable) shape — metadata values
  # are strings, microbenchmark/mount/ets rows carry the canonical keys — so
  # encode → decode is a clean round-trip.
  defp representative_run do
    %RunData{
      schema_version: RunData.schema_version(),
      metadata: %{
        run_id: "run-1",
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
      microbenchmarks: [
        %{
          suite: "continue_watching",
          runs: [
            %{
              input: "10 entities",
              scenarios: [
                %{
                  name: "build",
                  stats: %{
                    ips: 1000.0,
                    average_ns: 1_000_000,
                    median_ns: 900_000,
                    p99_ns: 2_000_000,
                    min_ns: 800_000,
                    max_ns: 3_000_000,
                    sample_size: 500
                  },
                  memory: 4096
                }
              ]
            }
          ]
        }
      ],
      page_mounts: [
        %{
          route: "/",
          warm_cache: true,
          runs: 20,
          min_us: 1200,
          p50_us: 1500,
          p95_us: 2200,
          max_us: 3000
        }
      ],
      ets_memory: [%{table: "continue_watching", rows: 10, bytes: 8192}],
      deltas: nil
    }
  end

  describe "encode/1 + decode/1" do
    test "round-trips a run through JSON" do
      run = representative_run()
      assert {:ok, decoded} = JSONFormatter.decode(JSONFormatter.encode!(run))
      assert decoded == run
    end

    test "encode!/1 returns a binary" do
      assert is_binary(JSONFormatter.encode!(representative_run()))
    end
  end

  describe "decode/1 error handling" do
    test "rejects malformed JSON" do
      assert {:error, _} = JSONFormatter.decode("{not json")
    end

    test "rejects a schema version it doesn't understand" do
      future = %{"schema_version" => 999, "metadata" => %{}}

      assert {:error, {:schema_mismatch, found: 999, expected: _}} =
               JSONFormatter.decode(Jason.encode!(future))
    end
  end
end
