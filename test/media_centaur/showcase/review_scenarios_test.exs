defmodule MediaCentaur.Showcase.ReviewScenariosTest do
  @moduledoc """
  Every scenario file, run through discovery against the showcase's TMDB
  fixtures, lands in Review for the reason the catalog lists — and the
  actions the walk depends on (pressing the bar's result, the failing
  match) end the way the catalog says.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Pipeline.Discovery
  alias MediaCentaur.Pipeline.Import
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Review
  alias MediaCentaur.Showcase.ReviewScenarios
  alias MediaCentaur.Topics

  @media_dir "/media/showcase"

  setup do
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
    :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :showcase_mode, true))
    Topics.subscribe(Topics.review_intake())
    :ok = ReviewScenarios.prepare!()
    :ok
  end

  defp discover(file) do
    payload = %Payload{file_path: Path.join(@media_dir, file), media_directory: @media_dir}
    outcome = Discovery.process(payload)
    assert match?({:needs_review, _}, outcome), "#{file} did not reach review: #{inspect(outcome)}"
    assert_receive {:needs_review, attrs}
    {:ok, pending} = Review.add_pending_file(attrs)
    pending
  end

  test "every scenario file lands in review for the reason the catalog lists" do
    for scenario <- ReviewScenarios.scenarios(), file <- scenario.files do
      assert Review.reason(discover(file)) == scenario.lands_in,
             "#{scenario.name}: #{file} landed as #{inspect(Review.reason(Repo.reload!(discover(file))))}"
    end
  end

  test "ticking any scenario row pre-fills a match-bar search the fixtures answer" do
    for scenario <- ReviewScenarios.scenarios(), file <- scenario.files do
      pending = discover(file)
      {query, type} = MediaCentaurWeb.ReviewHelpers.search_prefill([pending], MapSet.new([pending.id]))

      assert {:ok, _results} = Review.Search.tmdb(query, type),
             "#{scenario.name}: the bar's search for #{inspect(query)} (#{type}) is not answered"
    end
  end

  test "the match bar, pre-filled from the release-folder rows, finds the show, and pressing it imports" do
    assert {:ok, [%{tmdb_id: tmdb_id, title: "The Sample Show Hour"} | _]} =
             Review.Search.tmdb("Sample Show", :tv)

    [file | _] = Enum.find(ReviewScenarios.scenarios(), &(&1.name == "Release folders")).files

    payload = %Payload{
      file_path: Path.join(@media_dir, file),
      media_directory: @media_dir,
      tmdb_id: String.to_integer(tmdb_id),
      tmdb_type: :tv
    }

    assert {:ok, _payload} = Import.process_payload(payload)
  end

  test "the grab the scenarios seed is in a state the acquisition context knows" do
    for pursuit <- Repo.all(MediaCentaur.Acquisition.Pursuits.Pursuit) do
      assert MediaCentaur.Acquisition.Pursuits.State.bucket(pursuit.state) in [
               :in_flight,
               :terminal_success,
               :terminal_failure
             ]
    end
  end

  test "the not-added scenario's match fails to import" do
    scenario = Enum.find(ReviewScenarios.scenarios(), &(&1.name == "Not added"))
    {:match, %{tmdb_id: tmdb_id}} = scenario.then
    [file] = scenario.files

    payload = %Payload{
      file_path: Path.join(@media_dir, file),
      media_directory: @media_dir,
      tmdb_id: tmdb_id,
      tmdb_type: :movie
    }

    assert {:error, _reason} = Import.process_payload(payload)
  end
end
