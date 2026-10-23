defmodule MediaCentaur.Playback.Chain do
  @moduledoc """
  The viewing chain (ADR-062): a TV episode's successor is appended to the
  player's playlist, so end-of-episode rolls into the next file inside the
  same mpv — no window teardown, no HDR re-lock.

  Three pure questions over the session's entry, the pending successor
  and the property mirror; `MpvSession` asks them and does the sending:

    * `queue_next?/4` — append the successor now? Only while the current
      entry is the playlist's last, which makes the check
      self-stabilising and reconnect-safe: an entry queued by a previous
      backend run keeps the count ahead and is never duplicated.
    * `successor/3` — the successor's entry and the IPC that appends it,
      with the transport's media URL for the file.
    * `advance/3` — the entry a `path` change landed on: the pending one
      when the path matches, else re-derived from the host path (the
      ADR-023 discipline — covers entries queued before a backend restart).

  Declining auto-advance needs no state here — quitting the player ends
  the session, queued entry and all.
  """

  alias MediaCentaur.Playback.{Entry, MpvProperties, NextEpisode, Transport}

  @doc """
  Whether the successor should be appended now: an episode entry with an
  attached transport, nothing already queued, the current entry the
  playlist's last.
  """
  @spec queue_next?(Entry.t() | nil, Entry.t(), MpvProperties.t(), Transport.t()) :: boolean()
  def queue_next?(pending, %Entry{} = entry, %MpvProperties{} = properties, transport) do
    is_nil(pending) and not is_nil(entry.episode_id) and
      Transport.attached?(transport) and
      properties.playlist_count - properties.playlist_pos == 1
  end

  @doc """
  The successor of `entry` for `profile_id` and the command that appends
  it on `transport`: `:none` when the chain ends (`NextEpisode.resolve/2`),
  `{:error, reason}` when the successor exists but the player cannot be
  told to load it — the chain ends there too.
  """
  @spec successor(String.t(), Entry.t(), Transport.t()) ::
          {:ok, Entry.t(), list()} | :none | {:error, atom()}
  def successor(profile_id, %Entry{episode_id: episode_id}, transport) do
    with {:ok, entry} <- NextEpisode.resolve(profile_id, episode_id),
         {:ok, locator} <- Transport.locator(transport, entry.content_url) do
      {:ok, entry, Transport.queue(transport, locator, entry.start_position)}
    end
  end

  @doc "The entry an advance to `content_url` lands on, or `:none` for a file outside the chain's entity."
  @spec advance(Entry.t() | nil, String.t(), String.t()) :: {:ok, Entry.t()} | :none
  def advance(%Entry{content_url: content_url} = pending, _entity_id, content_url), do: {:ok, pending}
  def advance(_pending, entity_id, content_url), do: NextEpisode.identify(entity_id, content_url)
end
