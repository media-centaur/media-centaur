defmodule MediaCentaur.Topics do
  @moduledoc """
  PubSub topic constants. Centralises all topic strings so typos
  become compile-time failures instead of silent subscription misses.
  """

  def library_updates, do: "library:updates"
  def library_file_events, do: "library:file_events"
  def pipeline_input, do: "pipeline:input"
  def pipeline_images, do: "pipeline:images"
  def playback_events, do: "playback:events"
  def watcher_state, do: "watcher:state"
  def review_updates, do: "review:updates"
  def logging_updates, do: "logging:updates"
end
