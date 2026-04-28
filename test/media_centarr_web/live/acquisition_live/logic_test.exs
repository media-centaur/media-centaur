defmodule MediaCentarrWeb.AcquisitionLive.LogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.SearchResult
  alias MediaCentarrWeb.AcquisitionLive.Logic

  describe "expansion_preview/1" do
    test "returns :idle for empty query" do
      assert Logic.expansion_preview("") == :idle
      assert Logic.expansion_preview("   ") == :idle
    end

    test "returns {:ok, 1} for query without braces" do
      assert Logic.expansion_preview("Sample Movie 2049") == {:ok, 1}
    end

    test "returns {:ok, n} for valid expansion" do
      assert Logic.expansion_preview("Sample Show S01E{01-10}") == {:ok, 10}
      assert Logic.expansion_preview("X{a,b,c}") == {:ok, 3}
    end

    test "returns {:error, :invalid_syntax} for malformed brace" do
      assert Logic.expansion_preview("foo {a-}") == {:error, :invalid_syntax}
      assert Logic.expansion_preview("{a,b}{c,d}") == {:error, :invalid_syntax}
    end
  end

  describe "build_groups/1" do
    test "returns empty list for empty input" do
      assert Logic.build_groups([]) == []
    end

    test "groups results by term, sorted by quality desc then seeders desc" do
      r4k = result(guid: "a", quality: :uhd_4k, seeders: 5)
      r1080_high = result(guid: "b", quality: :hd_1080p, seeders: 100)
      r1080_low = result(guid: "c", quality: :hd_1080p, seeders: 1)
      rnil = result(guid: "d", quality: nil, seeders: 50)

      input = [{"Movie A", [r1080_low, r4k, rnil, r1080_high]}]

      [group] = Logic.build_groups(input)

      assert group.term == "Movie A"
      assert group.expanded? == false
      assert Enum.map(group.results, & &1.guid) == ["a", "b", "c", "d"]
    end

    test "preserves term order from input" do
      r1 = result(guid: "1")
      r2 = result(guid: "2")

      input = [{"Term One", [r1]}, {"Term Two", [r2]}]
      groups = Logic.build_groups(input)

      assert Enum.map(groups, & &1.term) == ["Term One", "Term Two"]
    end

    test "handles nil seeders by treating as 0 for sort" do
      a = result(guid: "a", quality: :hd_1080p, seeders: nil)
      b = result(guid: "b", quality: :hd_1080p, seeders: 1)

      [group] = Logic.build_groups([{"X", [a, b]}])

      assert Enum.map(group.results, & &1.guid) == ["b", "a"]
    end
  end

  describe "default_selections/1" do
    test "selects the first (top-ranked) result per group with results" do
      r_a = result(guid: "a-top")
      r_b = result(guid: "b-top")

      groups = [
        %{term: "A", expanded?: false, results: [r_a, result(guid: "a-2")]},
        %{term: "B", expanded?: false, results: [r_b]}
      ]

      assert Logic.default_selections(groups) == %{"A" => "a-top", "B" => "b-top"}
    end

    test "skips groups with no results" do
      groups = [
        %{term: "A", expanded?: false, results: [result(guid: "a")]},
        %{term: "B", expanded?: false, results: []}
      ]

      assert Logic.default_selections(groups) == %{"A" => "a"}
    end

    test "returns empty map for no groups" do
      assert Logic.default_selections([]) == %{}
    end
  end

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

  describe "placeholder_groups/1" do
    test "returns one :loading group per query, in order, with empty results" do
      groups = Logic.placeholder_groups(["A", "B", "C"])

      assert Enum.map(groups, & &1.term) == ["A", "B", "C"]
      assert Enum.all?(groups, &(&1.status == :loading))
      assert Enum.all?(groups, &(&1.results == []))
      assert Enum.all?(groups, &(&1.expanded? == false))
    end

    test "returns empty list for empty input" do
      assert Logic.placeholder_groups([]) == []
    end
  end

  describe "apply_search_result/3" do
    test "fills in matching group's results, sorts, and flips status to :ready" do
      groups = Logic.placeholder_groups(["X", "Y"])

      r_low = result(guid: "low", quality: :hd_1080p, seeders: 1)
      r_high = result(guid: "high", quality: :uhd_4k, seeders: 5)

      [x, y] = Logic.apply_search_result(groups, "X", {:ok, [r_low, r_high]})

      assert x.status == :ready
      assert Enum.map(x.results, & &1.guid) == ["high", "low"]

      # Other group untouched
      assert y.status == :loading
      assert y.results == []
    end

    test "marks matching group :failed on error and clears results, preserving reason" do
      groups = Logic.placeholder_groups(["X"])

      [x] = Logic.apply_search_result(groups, "X", {:error, :boom})

      assert x.status == {:failed, :boom}
      assert x.results == []
    end

    test "is a no-op when term is unknown (e.g. result from a stale search)" do
      groups = Logic.placeholder_groups(["X"])

      assert Logic.apply_search_result(groups, "OTHER", {:ok, [result(guid: "r")]}) == groups
    end
  end

  describe "add_default_selection/2" do
    test "adds top result guid when group is ready and term not yet selected" do
      group = %{term: "T", expanded?: false, status: :ready, results: [result(guid: "top")]}

      assert Logic.add_default_selection(%{}, group) == %{"T" => "top"}
    end

    test "does not overwrite an existing selection for the term" do
      group = %{term: "T", expanded?: false, status: :ready, results: [result(guid: "top")]}

      assert Logic.add_default_selection(%{"T" => "user-pick"}, group) == %{"T" => "user-pick"}
    end

    test "no-op when group has no results" do
      group = %{term: "T", expanded?: false, status: :ready, results: []}
      assert Logic.add_default_selection(%{}, group) == %{}
    end

    test "no-op for loading or failed groups" do
      loading = %{term: "T", expanded?: false, status: :loading, results: []}
      failed = %{term: "T", expanded?: false, status: {:failed, :boom}, results: []}

      assert Logic.add_default_selection(%{}, loading) == %{}
      assert Logic.add_default_selection(%{}, failed) == %{}
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

  describe "toggle_group/2" do
    test "flips expanded? for matching term, leaves others alone" do
      groups = [
        %{term: "A", expanded?: false, results: []},
        %{term: "B", expanded?: true, results: []}
      ]

      [a, b] = Logic.toggle_group(groups, "A")
      assert a.expanded? == true
      assert b.expanded? == true

      [a2, b2] = Logic.toggle_group([a, b], "B")
      assert a2.expanded? == true
      assert b2.expanded? == false
    end

    test "no-op for unknown term" do
      groups = [%{term: "A", expanded?: false, results: []}]
      assert Logic.toggle_group(groups, "Z") == groups
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

  describe "state_label/1" do
    test "returns user-facing label per state atom" do
      assert Logic.state_label(:downloading) == "Downloading"
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

  describe "state_badge_class/1" do
    test "returns a daisyUI badge color class per state" do
      assert Logic.state_badge_class(:downloading) =~ "info"
      assert Logic.state_badge_class(:completed) =~ "success"
      assert Logic.state_badge_class(:error) =~ "error"
      assert Logic.state_badge_class(:paused) =~ "warning"
      assert Logic.state_badge_class(:stalled) =~ "warning"
    end

    test "returns a neutral class for nil or unknown states" do
      assert Logic.state_badge_class(nil) =~ "neutral"
      assert Logic.state_badge_class(:other) =~ "neutral"
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

  describe "mark_group_loading/2" do
    test "flips the matching group to :loading and clears its results" do
      ready = %{
        term: "X",
        expanded?: true,
        status: :ready,
        results: [result(guid: "r")]
      }

      failed = %{
        term: "Y",
        expanded?: false,
        status: {:failed, %Req.TransportError{reason: :timeout}},
        results: []
      }

      [x, y] = Logic.mark_group_loading([ready, failed], "X")

      assert x.status == :loading
      assert x.results == []
      # expanded? is preserved so a manual retry doesn't collapse the group
      assert x.expanded? == true

      # Other group untouched
      assert y == failed
    end

    test "no-op when term is unknown" do
      groups = Logic.placeholder_groups(["X"])
      assert Logic.mark_group_loading(groups, "OTHER") == groups
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
