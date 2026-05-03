defmodule MediaCentarrWeb.AcquisitionLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.SearchResult
  alias MediaCentarrWeb.AcquisitionLive.Logic

  describe "format_grab_reason/1" do
    test "extracts errorMessage from a Prowlarr JSON body" do
      reason = {:http_error, 400, %{"errorMessage" => "Indexer not found"}}
      assert Logic.format_grab_reason(reason) == "HTTP 400: Indexer not found"
    end

    test "extracts message field from JSON body" do
      reason = {:http_error, 500, %{"message" => "Internal server error"}}
      assert Logic.format_grab_reason(reason) == "HTTP 500: Internal server error"
    end

    test "extracts error field from JSON body when string" do
      reason = {:http_error, 401, %{"error" => "Unauthorized"}}
      assert Logic.format_grab_reason(reason) == "HTTP 401: Unauthorized"
    end

    test "shows just status code when body has no recognizable message" do
      reason = {:http_error, 503, "Service Unavailable"}
      assert Logic.format_grab_reason(reason) == "HTTP 503"
    end

    test "inspects non-http reasons" do
      assert Logic.format_grab_reason(%Req.TransportError{reason: :econnrefused}) =~
               "econnrefused"

      assert Logic.format_grab_reason(:timeout) == ":timeout"
    end
  end

  describe "build_grab_message/1" do
    # Per the unified-grabs change (v0.24.0), Acquisition.grab/2 returns
    # `{:ok, %Grab{}}` rather than plain `:ok`. The build_grab_message
    # helper pattern-matches on that envelope shape.
    setup do
      {:ok, ok_outcome: {:ok, %MediaCentarr.Acquisition.Grab{}}}
    end

    test "all-ok returns {:ok, count submitted}", %{ok_outcome: ok} do
      pair = {result(guid: "a"), ok}
      assert Logic.build_grab_message([pair, pair]) == {:ok, "2 grab(s) submitted"}
    end

    test "all-failed returns {:error, count failed + first reason}" do
      pairs = [
        {result(guid: "a"), {:error, {:http_error, 400, %{"errorMessage" => "Bad guid"}}}},
        {result(guid: "b"), {:error, :timeout}}
      ]

      assert Logic.build_grab_message(pairs) ==
               {:error, "All 2 grab(s) failed — HTTP 400: Bad guid"}
    end

    test "partial returns {:partial, ok+err counts + first error reason}", %{ok_outcome: ok} do
      pairs = [
        {result(guid: "a"), ok},
        {result(guid: "b"), {:error, {:http_error, 500, %{"message" => "boom"}}}}
      ]

      assert Logic.build_grab_message(pairs) ==
               {:partial, "1 ok, 1 failed — HTTP 500: boom"}
    end

    test "empty list returns {:ok, 0 submitted}" do
      assert Logic.build_grab_message([]) == {:ok, "0 grab(s) submitted"}
    end
  end

  describe "find_result/2" do
    test "finds a result by guid across all groups" do
      r_a = result(guid: "a")
      r_b = result(guid: "b")
      r_c = result(guid: "c")

      groups = [
        %{term: "T1", expanded?: false, results: [r_a, r_b]},
        %{term: "T2", expanded?: false, results: [r_c]}
      ]

      assert Logic.find_result(groups, "b") == r_b
      assert Logic.find_result(groups, "c") == r_c
    end

    test "returns nil when guid is not present" do
      groups = [%{term: "T", expanded?: false, results: [result(guid: "a")]}]
      assert Logic.find_result(groups, "missing") == nil
    end
  end

  describe "all_loaded?/1" do
    test "true when no group is :loading" do
      groups = [
        %{term: "A", expanded?: false, status: :ready, results: []},
        %{term: "B", expanded?: false, status: {:failed, :boom}, results: []}
      ]

      assert Logic.all_loaded?(groups) == true
    end

    test "false when any group is :loading" do
      groups = [
        %{term: "A", expanded?: false, status: :ready, results: []},
        %{term: "B", expanded?: false, status: :loading, results: []}
      ]

      assert Logic.all_loaded?(groups) == false
    end

    test "true for empty groups list" do
      assert Logic.all_loaded?([]) == true
    end
  end

  describe "any_loading?/1" do
    test "false when no group is :loading" do
      groups = [
        %{term: "A", expanded?: false, status: :ready, results: []},
        %{term: "B", expanded?: false, status: :abandoned, results: []}
      ]

      assert Logic.any_loading?(groups) == false
    end

    test "true when any group is :loading" do
      groups = [
        %{term: "A", expanded?: false, status: :ready, results: []},
        %{term: "B", expanded?: false, status: :loading, results: []}
      ]

      assert Logic.any_loading?(groups) == true
    end

    test "false for empty groups list" do
      assert Logic.any_loading?([]) == false
    end
  end

  describe "featured_result/2" do
    test "returns the selected result when group's term is present in selections" do
      r_top = result(guid: "top")
      r_alt = result(guid: "alt")
      group = %{term: "T", expanded?: false, status: :ready, results: [r_top, r_alt]}

      assert Logic.featured_result(group, %{"T" => "alt"}) == r_alt
    end

    test "falls back to top result when term has no selection" do
      r_top = result(guid: "top")
      r_alt = result(guid: "alt")
      group = %{term: "T", expanded?: false, status: :ready, results: [r_top, r_alt]}

      assert Logic.featured_result(group, %{}) == r_top
    end

    test "falls back to top result when selection guid does not exist in this group" do
      r_top = result(guid: "top")
      group = %{term: "T", expanded?: false, status: :ready, results: [r_top]}

      assert Logic.featured_result(group, %{"T" => "stale-guid"}) == r_top
    end

    test "returns nil when group has no results" do
      group = %{term: "T", expanded?: false, status: :ready, results: []}
      assert Logic.featured_result(group, %{"T" => "anything"}) == nil
    end
  end

  describe "group_downloads_by_state/1" do
    alias MediaCentarr.Acquisition.QueueItem

    test "returns active and completed buckets in display order" do
      items = [
        %QueueItem{id: "a", title: "a", state: :downloading},
        %QueueItem{id: "b", title: "b", state: :completed},
        %QueueItem{id: "c", title: "c", state: :paused},
        %QueueItem{id: "d", title: "d", state: :stalled},
        %QueueItem{id: "e", title: "e", state: :error},
        %QueueItem{id: "f", title: "f", state: :other}
      ]

      result = Logic.group_downloads_by_state(items)

      assert Map.keys(result) == [:active, :completed]
      assert Enum.map(result.active, & &1.id) == ~w(a c d e f)
      assert Enum.map(result.completed, & &1.id) == ~w(b)
    end

    test "preserves input order within each bucket" do
      items = [
        %QueueItem{id: "1", title: "1", state: :completed},
        %QueueItem{id: "2", title: "2", state: :downloading},
        %QueueItem{id: "3", title: "3", state: :completed}
      ]

      result = Logic.group_downloads_by_state(items)

      assert Enum.map(result.completed, & &1.id) == ~w(1 3)
      assert Enum.map(result.active, & &1.id) == ~w(2)
    end

    test "returns empty buckets when input is empty" do
      assert Logic.group_downloads_by_state([]) == %{active: [], completed: []}
    end

    test "groups nil state into active (defensive — drivers should always set it)" do
      items = [%QueueItem{id: "x", title: "x", state: nil}]
      assert Logic.group_downloads_by_state(items) == %{active: items, completed: []}
    end
  end

  describe "sort_downloads/1" do
    alias MediaCentarr.Acquisition.QueueItem

    test "orders by activity: error → downloading → stalled → paused → queued → other" do
      items = [
        %QueueItem{id: "q", title: "q", state: :queued},
        %QueueItem{id: "p", title: "p", state: :paused},
        %QueueItem{id: "d", title: "d", state: :downloading, timeleft: "1m"},
        %QueueItem{id: "o", title: "o", state: :other},
        %QueueItem{id: "e", title: "e", state: :error},
        %QueueItem{id: "s", title: "s", state: :stalled}
      ]

      assert Enum.map(Logic.sort_downloads(items), & &1.id) == ~w(e d s p q o)
    end

    test "within :downloading, sorts by ETA ascending (closest-to-done first)" do
      items = [
        %QueueItem{id: "slow", title: "slow", state: :downloading, timeleft: "2h 30m"},
        %QueueItem{id: "fast", title: "fast", state: :downloading, timeleft: "35s"},
        %QueueItem{id: "mid", title: "mid", state: :downloading, timeleft: "14m"}
      ]

      assert Enum.map(Logic.sort_downloads(items), & &1.id) == ~w(fast mid slow)
    end

    test "items with nil timeleft sort after items with a known ETA" do
      items = [
        %QueueItem{id: "unknown", title: "unknown", state: :downloading, timeleft: nil},
        %QueueItem{id: "known", title: "known", state: :downloading, timeleft: "5m"}
      ]

      assert Enum.map(Logic.sort_downloads(items), & &1.id) == ~w(known unknown)
    end

    test "preserves input order within non-downloading groups" do
      items = [
        %QueueItem{id: "q1", title: "q1", state: :queued},
        %QueueItem{id: "q2", title: "q2", state: :queued},
        %QueueItem{id: "q3", title: "q3", state: :queued}
      ]

      assert Enum.map(Logic.sort_downloads(items), & &1.id) == ~w(q1 q2 q3)
    end

    test "nil state sorts as :other (defensive)" do
      items = [
        %QueueItem{id: "n", title: "n", state: nil},
        %QueueItem{id: "d", title: "d", state: :downloading, timeleft: "1m"}
      ]

      assert Enum.map(Logic.sort_downloads(items), & &1.id) == ~w(d n)
    end

    test "empty input returns empty list" do
      assert Logic.sort_downloads([]) == []
    end

    test "within :downloading, degraded health (soft_stall/frozen/meta_stuck) bubbles to the top of the group" do
      # ETA-only sort would put "fast" first. Degraded items should
      # surface above all healthy items because they need attention.
      items = [
        %QueueItem{
          id: "fast",
          title: "fast",
          state: :downloading,
          timeleft: "30s",
          health: :healthy
        },
        %QueueItem{
          id: "stuck",
          title: "stuck",
          state: :downloading,
          timeleft: "8h",
          health: :soft_stall
        },
        %QueueItem{
          id: "frozen",
          title: "frozen",
          state: :downloading,
          timeleft: nil,
          health: :frozen
        },
        %QueueItem{
          id: "slowish",
          title: "slowish",
          state: :downloading,
          timeleft: "1h",
          health: :slow
        }
      ]

      sorted_ids = Enum.map(Logic.sort_downloads(items), & &1.id)

      # Degraded (stuck, frozen) first; then :slow; then healthy.
      # Within each tier, ETA ascending.
      degraded_indices =
        Enum.map(["stuck", "frozen"], &Enum.find_index(sorted_ids, fn id -> id == &1 end))

      slow_index = Enum.find_index(sorted_ids, fn id -> id == "slowish" end)
      healthy_index = Enum.find_index(sorted_ids, fn id -> id == "fast" end)

      assert Enum.all?(degraded_indices, fn i -> i < slow_index end)
      assert slow_index < healthy_index
    end

    test "within :downloading, healthy items still sort by ETA ascending" do
      items = [
        %QueueItem{
          id: "slow",
          title: "slow",
          state: :downloading,
          timeleft: "2h 30m",
          health: :healthy
        },
        %QueueItem{
          id: "fast",
          title: "fast",
          state: :downloading,
          timeleft: "35s",
          health: :healthy
        },
        %QueueItem{
          id: "warming",
          title: "warming",
          state: :downloading,
          timeleft: "14m",
          health: :warming_up
        }
      ]

      assert Enum.map(Logic.sort_downloads(items), & &1.id) == ~w(fast warming slow)
    end
  end

  describe "partition_collapsible_group/3" do
    alias MediaCentarr.Acquisition.QueueItem

    test "returns {items, nil} when count is below collapse threshold" do
      items = [
        %QueueItem{id: "1", title: "1", state: :queued},
        %QueueItem{id: "2", title: "2", state: :queued}
      ]

      assert Logic.partition_collapsible_group(items, :queued, false) == {items, nil}
    end

    test "splits into head + summary when count exceeds threshold and collapsed" do
      items =
        for i <- 1..5 do
          %QueueItem{id: "q#{i}", title: "q#{i}", state: :queued}
        end

      {head, summary} = Logic.partition_collapsible_group(items, :queued, false)

      assert length(head) == 2
      assert Enum.map(head, & &1.id) == ~w(q1 q2)
      assert summary.kind == :collapsed
      assert summary.state == :queued
      assert summary.hidden_count == 3
      assert Enum.map(summary.hidden, & &1.id) == ~w(q3 q4 q5)
    end

    test "returns full list with expanded marker when expanded?=true and count exceeds threshold" do
      items =
        for i <- 1..5 do
          %QueueItem{id: "q#{i}", title: "q#{i}", state: :queued}
        end

      {visible, summary} = Logic.partition_collapsible_group(items, :queued, true)

      assert length(visible) == 5
      assert summary.kind == :expanded
      assert summary.state == :queued
      assert summary.total == 5
    end

    test "applies to :error groups too" do
      items =
        for i <- 1..4 do
          %QueueItem{id: "e#{i}", title: "e#{i}", state: :error}
        end

      {head, summary} = Logic.partition_collapsible_group(items, :error, false)

      assert length(head) == 2
      assert summary.state == :error
      assert summary.hidden_count == 2
    end

    test "empty input returns {[], nil}" do
      assert Logic.partition_collapsible_group([], :queued, false) == {[], nil}
    end
  end

  describe "prepare_queue_for_render/2" do
    alias MediaCentarr.Acquisition.QueueItem

    test "returns a flat list of {:item, item} ops in activity order when no group exceeds the head size" do
      items = [
        %QueueItem{id: "q", title: "q", state: :queued},
        %QueueItem{id: "d", title: "d", state: :downloading, timeleft: "1m"},
        %QueueItem{id: "e", title: "e", state: :error}
      ]

      ops = Logic.prepare_queue_for_render(items, MapSet.new())

      assert Enum.map(ops, fn {:item, item} -> item.id end) == ~w(e d q)
    end

    test "collapses :queued group when count exceeds head size and not expanded" do
      items =
        for i <- 1..5 do
          %QueueItem{id: "q#{i}", title: "q#{i}", state: :queued}
        end

      ops = Logic.prepare_queue_for_render(items, MapSet.new())

      # head + summary
      assert length(ops) == 3

      [{:item, q1}, {:item, q2}, {:summary, summary}] = ops
      assert q1.id == "q1"
      assert q2.id == "q2"
      assert summary.kind == :collapsed
      assert summary.hidden_count == 3
    end

    test "renders all items + expanded summary when state is in the expanded set" do
      items =
        for i <- 1..5 do
          %QueueItem{id: "q#{i}", title: "q#{i}", state: :queued}
        end

      ops = Logic.prepare_queue_for_render(items, MapSet.new([:queued]))

      assert length(ops) == 6
      [a, b, c, d, e, summary] = ops
      assert {:item, %{id: "q1"}} = a
      assert {:item, %{id: "q2"}} = b
      assert {:item, %{id: "q3"}} = c
      assert {:item, %{id: "q4"}} = d
      assert {:item, %{id: "q5"}} = e
      assert {:summary, %{kind: :expanded, total: 5}} = summary
    end

    test "collapsibility is independent per group — :error can be expanded while :queued is collapsed" do
      errors = for i <- 1..3, do: %QueueItem{id: "e#{i}", title: "e#{i}", state: :error}
      queued = for i <- 1..4, do: %QueueItem{id: "q#{i}", title: "q#{i}", state: :queued}
      items = errors ++ queued

      ops = Logic.prepare_queue_for_render(items, MapSet.new([:error]))

      # :error fully expanded (3 items + summary), then :queued head + summary
      error_ops = Enum.take(ops, 4)
      queued_ops = Enum.drop(ops, 4)

      assert Enum.map(error_ops, fn
               {:item, item} -> item.id
               {:summary, summary} -> {:summary, summary.state, summary.kind}
             end) == ["e1", "e2", "e3", {:summary, :error, :expanded}]

      assert length(queued_ops) == 3
      [{:item, q1}, {:item, q2}, {:summary, summary}] = queued_ops
      assert {q1.id, q2.id, summary.state, summary.kind} == {"q1", "q2", :queued, :collapsed}
    end

    test "non-collapsible states render every item with no summary even at high count" do
      items =
        for i <- 1..6 do
          %QueueItem{id: "d#{i}", title: "d#{i}", state: :downloading, timeleft: "1m"}
        end

      ops = Logic.prepare_queue_for_render(items, MapSet.new())

      assert length(ops) == 6
      assert Enum.all?(ops, &match?({:item, _}, &1))
    end

    test "empty input returns empty ops list" do
      assert Logic.prepare_queue_for_render([], MapSet.new()) == []
    end
  end

  describe "render_health_line?/1" do
    alias MediaCentarr.Acquisition.QueueItem

    test "true for degraded and slow statuses" do
      for status <- [:soft_stall, :frozen, :meta_stuck, :slow, :queued_long] do
        assert Logic.render_health_line?(%QueueItem{
                 id: "x",
                 title: "x",
                 state: :downloading,
                 health: status
               }),
               "expected #{inspect(status)} to render"
      end
    end

    test "false for nil, :healthy, :warming_up" do
      for status <- [nil, :healthy, :warming_up] do
        refute Logic.render_health_line?(%QueueItem{
                 id: "x",
                 title: "x",
                 state: :downloading,
                 health: status
               }),
               "expected #{inspect(status)} to suppress the line"
      end
    end
  end

  describe "health_text_class/1" do
    test "warning statuses → text-warning" do
      assert Logic.health_text_class(:soft_stall) == "text-warning"
      assert Logic.health_text_class(:frozen) == "text-warning"
      assert Logic.health_text_class(:meta_stuck) == "text-warning"
    end

    test "ghost statuses → muted text class" do
      assert Logic.health_text_class(:slow) == "text-base-content/60"
      assert Logic.health_text_class(:queued_long) == "text-base-content/60"
    end

    test "non-degraded statuses fall back to the muted-faint class" do
      assert Logic.health_text_class(:healthy) == "text-base-content/40"
      assert Logic.health_text_class(:warming_up) == "text-base-content/40"
      assert Logic.health_text_class(nil) == "text-base-content/40"
    end
  end

  describe "state_label/1" do
    test "returns user-facing label per state atom" do
      assert Logic.state_label(:downloading) == "Downloading"
      assert Logic.state_label(:queued) == "Queued"
      assert Logic.state_label(:stalled) == "Stalled"
      assert Logic.state_label(:paused) == "Paused"
      assert Logic.state_label(:completed) == "Completed"
      assert Logic.state_label(:error) == "Error"
      assert Logic.state_label(:other) == "Other"
    end

    test "falls back to a generic label for nil or unknown" do
      assert Logic.state_label(nil) == "Unknown"
      assert Logic.state_label(:something_new) == "Unknown"
    end
  end

  describe "state_badge_variant/1" do
    test "returns a `<.badge>` variant per state" do
      assert Logic.state_badge_variant(:downloading) == "info"
      assert Logic.state_badge_variant(:completed) == "success"
      assert Logic.state_badge_variant(:error) == "error"
      assert Logic.state_badge_variant(:paused) == "warning"
      assert Logic.state_badge_variant(:stalled) == "warning"
    end

    test ":queued uses ghost to read as passive waiting, not the warning yellow of :stalled" do
      assert Logic.state_badge_variant(:queued) == "ghost"
    end

    test "returns the metric (default) variant for nil or unknown states" do
      assert Logic.state_badge_variant(nil) == "metric"
      assert Logic.state_badge_variant(:other) == "metric"
    end
  end

  describe "format_search_error/1" do
    test "explains :econnrefused as an unreachable Prowlarr" do
      assert Logic.format_search_error(%Req.TransportError{reason: :econnrefused}) ==
               "Couldn't reach Prowlarr — check that the service is running and the URL is correct"
    end

    test "explains :nxdomain as a bad URL" do
      assert Logic.format_search_error(%Req.TransportError{reason: :nxdomain}) ==
               "Prowlarr URL not found — check the URL in Settings"
    end

    test "explains :timeout" do
      assert Logic.format_search_error(%Req.TransportError{reason: :timeout}) ==
               "Prowlarr timed out"
    end

    test "explains 401/403 as an API key problem" do
      assert Logic.format_search_error({:http_error, 401, %{}}) ==
               "Prowlarr rejected the API key — check Settings"

      assert Logic.format_search_error({:http_error, 403, %{}}) ==
               "Prowlarr rejected the API key — check Settings"
    end

    test "shows the HTTP status for other HTTP errors" do
      assert Logic.format_search_error({:http_error, 500, %{}}) ==
               "Prowlarr returned HTTP 500"
    end

    test "falls back to a generic message for unknown reasons" do
      assert Logic.format_search_error(:boom) == "Search failed"
    end
  end

  describe "timeout_terms/1" do
    test "returns terms whose status is a Req.TransportError :timeout" do
      groups = [
        %{term: "A", expanded?: false, status: :ready, results: [result(guid: "a")]},
        %{
          term: "B",
          expanded?: false,
          status: {:failed, %Req.TransportError{reason: :timeout}},
          results: []
        },
        %{term: "C", expanded?: false, status: :loading, results: []},
        %{
          term: "D",
          expanded?: false,
          status: {:failed, %Req.TransportError{reason: :timeout}},
          results: []
        }
      ]

      assert Logic.timeout_terms(groups) == ["B", "D"]
    end

    test "excludes other failure reasons (econnrefused, http errors, etc.)" do
      groups = [
        %{
          term: "A",
          expanded?: false,
          status: {:failed, %Req.TransportError{reason: :econnrefused}},
          results: []
        },
        %{
          term: "B",
          expanded?: false,
          status: {:failed, %Req.TransportError{reason: :nxdomain}},
          results: []
        },
        %{
          term: "C",
          expanded?: false,
          status: {:failed, {:http_error, 401, %{}}},
          results: []
        },
        %{term: "D", expanded?: false, status: {:failed, :boom}, results: []}
      ]

      assert Logic.timeout_terms(groups) == []
    end

    test "returns [] for empty groups" do
      assert Logic.timeout_terms([]) == []
    end
  end

  defp result(opts) do
    %SearchResult{
      title: Keyword.get(opts, :title, "Some.Release.2024.2160p"),
      guid: Keyword.fetch!(opts, :guid),
      indexer_id: Keyword.get(opts, :indexer_id, 1),
      quality: Keyword.get(opts, :quality, :hd_1080p),
      seeders: Keyword.get(opts, :seeders, 10),
      leechers: Keyword.get(opts, :leechers, 0),
      size_bytes: Keyword.get(opts, :size_bytes),
      indexer_name: Keyword.get(opts, :indexer_name, "indexer"),
      publish_date: nil
    }
  end
end
