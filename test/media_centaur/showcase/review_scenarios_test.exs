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
  alias MediaCentaur.TMDB.TitleSearch
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

  test "the release-folder show is found by the search bar, and pressing it imports" do
    assert [%{tmdb_id: tmdb_id, media_type: :tv_series} | _] = TitleSearch.search("Sample Show")

    [file | _] = Enum.find(ReviewScenarios.scenarios(), &(&1.name == "Release folders")).files

    payload = %Payload{
      file_path: Path.join(@media_dir, file),
      media_directory: @media_dir,
      tmdb_id: tmdb_id,
      tmdb_type: :tv
    }

    assert {:ok, _payload} = Import.process_payload(payload)
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
