defmodule MediaCentaur.Acquisition.CallerSeamsTest do
  @moduledoc "The context functions a caller without a page depends on."
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.Corpus
  alias MediaCentaur.Acquisition.Pursuits
  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.ProwlarrStubs
  alias MediaCentaur.Search.SearchResult

  defp release(guid), do: %{"title" => "Sample.Show.#{guid}.1080p", "guid" => guid, "indexerId" => 1}

  defp stub_terms(answers) do
    Req.Test.stub(:prowlarr, fn conn ->
      case answers[Plug.Conn.fetch_query_params(conn).query_params["query"]] do
        :fail -> Plug.Conn.send_resp(conn, 500, "indexer down")
        releases -> Req.Test.json(conn, releases || [])
      end
    end)
  end

  describe "with Prowlarr ready" do
    setup do
      Req.Test.stub(:prowlarr, fn conn -> Req.Test.json(conn, []) end)
      :ok = ProwlarrStubs.mark_ready!()
    end

    test "search_terms/2 says which term failed and keeps the others' releases" do
      stub_terms(%{"Sample E1" => [release("one")], "Sample E2" => :fail})

      assert {:ok, [first, second]} = Acquisition.search_terms("Sample E{1,2}", force: true)
      assert %{term: "Sample E1", outcome: {:ok, [%SearchResult{guid: "one"}]}} = first
      assert %{term: "Sample E2", outcome: {:error, _reason}} = second
    end

    test "search_expanded/2 merges the terms that answered" do
      stub_terms(%{"Sample E1" => [release("one")], "Sample E2" => :fail})

      assert {:ok, [%SearchResult{guid: "one"}]} =
               Acquisition.search_expanded("Sample E{1,2}", force: true)
    end

    test "search_terms/2 refuses malformed braces" do
      assert {:error, :invalid_syntax} = Acquisition.search_terms("Sample E{1")
    end

    test "grab_releases/2 records one pursuit covering every release the corpus knows" do
      Corpus.record!("Sample E1", [], [SearchResult.from_prowlarr(release("one"))])
      Corpus.record!("Sample E2", [], [SearchResult.from_prowlarr(release("two"))])

      picks = [%{guid: "one", term: "Sample E1"}, %{guid: "two", term: "Sample E2"}]

      assert {:ok, [first, second]} = Acquisition.grab_releases(picks, "Sample E{1,2}")
      assert first.pursuit_id == second.pursuit_id
      assert {:ok, %Pursuit{manual_query: "Sample E{1,2}"}} = Pursuits.fetch(first.pursuit_id)
    end

    test "grab_releases/2 grabs a release named twice once" do
      Corpus.record!("Sample E1", [], [SearchResult.from_prowlarr(release("one"))])
      pick = %{guid: "one", term: "Sample E1"}

      assert {:ok, [_only]} = Acquisition.grab_releases([pick, pick], "Sample E1")
    end

    test "grab_releases/2 grabs nothing when one guid is unknown, and names it" do
      Corpus.record!("Sample E1", [], [SearchResult.from_prowlarr(release("one"))])

      picks = [%{guid: "one", term: "Sample E1"}, %{guid: "gone", term: "Sample E2"}]

      assert {:error, {:release_unavailable, "gone"}} = Acquisition.grab_releases(picks, "Sample")
      assert Pursuits.list_active() == []
    end

    test "cancel_pursuit/1 closes an in-flight pursuit" do
      pursuit = create_pursuit(%{title: "Sample Movie"})

      assert {:ok, %Pursuit{state: "cancelled"}} = Acquisition.cancel_pursuit(pursuit.id)
    end

    test "cancel_pursuit/1 refuses a pursuit already over" do
      pursuit = create_pursuit(%{title: "Sample Movie"})
      {:ok, _cancelled} = Acquisition.cancel_pursuit(pursuit.id)

      assert {:error, :not_eligible} = Acquisition.cancel_pursuit(pursuit.id)
    end
  end

  test "fetch_release/1 answers for a guid the corpus does not hold" do
    assert {:error, :release_unavailable} = Acquisition.fetch_release("gone")
  end

  test "an id that is not a UUID is simply not found" do
    assert {:error, :not_found} = Pursuits.fetch("not-a-uuid")
    assert {:error, :not_found} = Acquisition.cancel_pursuit("not-a-uuid")
  end
end
