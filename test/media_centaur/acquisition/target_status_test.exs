defmodule MediaCentaur.Acquisition.TargetStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.TargetStatus

  # The bucket table in the TargetStatus moduledoc is the contract this
  # module exists to hold. The v0.31.0 incident was a terminal-failure row
  # silently categorised as in-flight, so every assertion here is about
  # which bucket a status lands in — not about implementation.
  #
  # `@bucket_table` mirrors the moduledoc row-for-row. When a status is
  # added, this table is the one place that has to learn about it, and a
  # miscategorisation shows up as a failure rather than a wrong toast.
  @bucket_table [
    %{status: "seeking", bucket: :in_flight, rearmable?: false, cancellable?: true},
    %{status: "acquired", bucket: :terminal_success, rearmable?: true, cancellable?: true},
    %{status: "succeeded", bucket: :terminal_success, rearmable?: false, cancellable?: false},
    %{status: "failed", bucket: :terminal_failure, rearmable?: true, cancellable?: false},
    %{status: "cancelled", bucket: :terminal_failure, rearmable?: true, cancellable?: false}
  ]

  describe "bucket/1" do
    for %{status: status, bucket: bucket} <- @bucket_table do
      test "categorises #{status} as #{bucket}" do
        assert TargetStatus.bucket(unquote(status)) == unquote(bucket)
        assert TargetStatus.bucket(String.to_existing_atom(unquote(status))) == unquote(bucket)
      end
    end

    test "raises on an unknown status rather than guessing a bucket" do
      assert_raise ArgumentError, ~r/unknown target status/, fn ->
        TargetStatus.bucket("expired")
      end
    end
  end

  describe "bucket membership lists" do
    test "all/0 is exactly the five documented statuses" do
      assert Enum.sort(TargetStatus.all()) ==
               Enum.sort(Enum.map(@bucket_table, & &1.status))
    end

    test "the three buckets partition all/0 with no overlap and no gap" do
      buckets =
        TargetStatus.in_flight() ++
          TargetStatus.terminal_success() ++ TargetStatus.terminal_failure()

      assert Enum.sort(buckets) == Enum.sort(TargetStatus.all())
      assert length(buckets) == length(Enum.uniq(buckets))
    end

    test "terminal/0 is the union of the two terminal buckets" do
      assert Enum.sort(TargetStatus.terminal()) ==
               Enum.sort(TargetStatus.terminal_success() ++ TargetStatus.terminal_failure())
    end

    for %{status: status, bucket: bucket} <- @bucket_table do
      test "#{status} appears in the #{bucket} list" do
        list =
          case unquote(bucket) do
            :in_flight -> TargetStatus.in_flight()
            :terminal_success -> TargetStatus.terminal_success()
            :terminal_failure -> TargetStatus.terminal_failure()
          end

        assert unquote(status) in list
      end
    end
  end

  describe "predicates" do
    for %{status: status, bucket: bucket, rearmable?: rearmable, cancellable?: cancellable} <-
          @bucket_table do
      test "#{status} predicates match its documented row" do
        status = unquote(status)

        assert TargetStatus.in_flight?(status) == (unquote(bucket) == :in_flight)
        assert TargetStatus.terminal?(status) == (unquote(bucket) != :in_flight)
        assert TargetStatus.terminal_success?(status) == (unquote(bucket) == :terminal_success)
        assert TargetStatus.terminal_failure?(status) == (unquote(bucket) == :terminal_failure)
        assert TargetStatus.rearmable?(status) == unquote(rearmable)
        assert TargetStatus.cancellable?(status) == unquote(cancellable)
      end
    end

    test "predicates accept the atom form as well as the DB string form" do
      assert TargetStatus.in_flight?(:seeking)
      assert TargetStatus.terminal?(:succeeded)
      assert TargetStatus.terminal_success?(:acquired)
      assert TargetStatus.terminal_failure?(:cancelled)
      assert TargetStatus.rearmable?(:failed)
      assert TargetStatus.cancellable?(:acquired)
    end

    test "an unknown status is false for every predicate, never accidentally in-flight" do
      refute TargetStatus.in_flight?("expired")
      refute TargetStatus.terminal?("expired")
      refute TargetStatus.terminal_success?("expired")
      refute TargetStatus.terminal_failure?("expired")
      refute TargetStatus.rearmable?("expired")
      refute TargetStatus.cancellable?("expired")
    end
  end

  describe "rearmable/0" do
    test "is every terminal status except succeeded — the file already landed" do
      assert Enum.sort(TargetStatus.rearmable()) ==
               Enum.sort(TargetStatus.terminal() -- ["succeeded"])
    end
  end

  describe "cancellable/0" do
    test "covers the statuses a cancel command can still flip" do
      assert Enum.sort(TargetStatus.cancellable()) ==
               Enum.filter(@bucket_table, & &1.cancellable?) |> Enum.map(& &1.status) |> Enum.sort()
    end

    test "is wider than in_flight/0 — zero-seeders fires on acquired torrents" do
      for status <- TargetStatus.in_flight() do
        assert status in TargetStatus.cancellable()
      end

      assert "acquired" in TargetStatus.cancellable()
      refute "acquired" in TargetStatus.in_flight()
    end

    test "never includes a status whose work is already over" do
      refute "succeeded" in TargetStatus.cancellable()
      refute "failed" in TargetStatus.cancellable()
      refute "cancelled" in TargetStatus.cancellable()
    end
  end
end
