defmodule MediaCentaur.Pipeline.StatsBroadcastTest do
  @moduledoc """
  The coalesced `pipeline:stats` broadcast of both Stats GenServers. Sync,
  because the topic is shared with the application's own instances and
  any pipeline activity from a concurrently running module would land in
  this mailbox too.
  """
  use ExUnit.Case, async: false

  alias MediaCentaur.Pipeline.Image.Stats, as: ImageStats
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.Topics

  setup do
    Topics.subscribe(Topics.pipeline_stats())
    :ok
  end

  test "a burst of stage events becomes one coalesced content update" do
    stats = start_supervised!({Stats, name: :"stats_#{System.unique_integer([:positive])}"})

    for _ <- 1..5, do: Stats.stage_start(stats, :parse, "/media/a.mkv")

    assert_receive {:pipeline_stats_updated, :content}, 1_000
    refute_receive {:pipeline_stats_updated, :content}, 300
  end

  test "a burst of download events becomes one coalesced image update" do
    stats = start_supervised!({ImageStats, name: :"image_stats_#{System.unique_integer([:positive])}"})

    for _ <- 1..5, do: ImageStats.download_start(stats, :poster, "entity-1")

    assert_receive {:pipeline_stats_updated, :image}, 1_000
    refute_receive {:pipeline_stats_updated, :image}, 300
  end
end
