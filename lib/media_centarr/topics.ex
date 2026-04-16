defmodule MediaCentarr.Topics do
  @moduledoc """
  PubSub topic constants. Centralises all topic strings so typos
  become compile-time failures instead of silent subscription misses.
  """

  def library_updates, do: "library:updates"
  def library_commands, do: "library:commands"
  def library_file_events, do: "library:file_events"
  def pipeline_input, do: "pipeline:input"
  def pipeline_matched, do: "pipeline:matched"
  def pipeline_images, do: "pipeline:images"
  def pipeline_publish, do: "pipeline:publish"
  def playback_events, do: "playback:events"
  def dir_state, do: "watcher:state"
  def review_intake, do: "review:intake"
  def review_updates, do: "review:updates"
  def settings_updates, do: "settings:updates"
  def release_tracking_updates, do: "release_tracking:updates"
  def watch_history_events, do: "watch_history:events"
  def console_logs, do: "console:logs"
  def acquisition_updates, do: "acquisition:updates"
end
