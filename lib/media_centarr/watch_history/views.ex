defmodule MediaCentarr.WatchHistory.Views do
  @moduledoc """
  Public read API for WatchHistory projections (ADR-041).

  Consumers (typically the `/history` LiveView) subscribe to
  `watch_history:views` once at mount, read view-shaped data via
  these functions, and re-read on
  `{:watch_history_view_updated, view_id}` messages.

  Reads are byte-code-inlined `:persistent_term` lookups when the
  projection's `Cache.Worker` is running. When it isn't (test mode,
  or briefly during boot before the first refresh completes), reads
  fall back to fresh DB queries so behaviour is identical from the
  caller's POV.
  """

  alias MediaCentarr.Topics
  alias MediaCentarr.WatchHistory.Views.Summary
  alias MediaCentarr.WatchHistory.Views.SummaryData

  @doc "Subscribe the caller to WatchHistory projection-refreshed events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.watch_history_views())
  end

  @doc """
  Returns the dashboard summary — stats, heatmap cells per type, and
  rewatch counts per type. Single read serves the entire top-of-page
  aggregate panel.
  """
  @spec summary() :: SummaryData.t()
  def summary, do: Summary.read()
end
