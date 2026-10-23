defmodule MediaCentaur.Playback.Entry do
  @moduledoc """
  What a session plays now: one file with its library identity and the
  position it starts from.

  The one shape for "a playable file as the session knows it", built by
  `Playback.Resolver` (what a play request resolves to), `NextEpisode`
  (the successor queued on the playlist, and the identity of a file an
  advance landed on) and `SessionRecovery` (what an orphaned mpv plays).
  `MpvSession` holds one as its current entry and one as the pending
  successor; an advance replaces the current entry whole.

  The library identity is the entity the viewing chain belongs to
  (`entity_id`, `entity_name`) and the one playable the file is — exactly
  one of `movie_id`, `episode_id`, `extra_id`, `video_object_id` — with an
  episode's season and episode numbers and name. An entry with none of the
  four keys is **unattributed**: a file the library does not know (mpv was
  found playing it, or the playlist advanced to it by hand); the session
  keeps observing it but saves no progress for it.
  """

  @enforce_keys [:entity_id, :content_url]
  defstruct [
    :entity_id,
    :entity_name,
    :season_number,
    :episode_number,
    :episode_name,
    :extra_id,
    :movie_id,
    :episode_id,
    :video_object_id,
    :content_url,
    start_position: 0.0
  ]

  @type t :: %__MODULE__{
          entity_id: String.t(),
          entity_name: String.t() | nil,
          season_number: integer() | nil,
          episode_number: integer() | nil,
          episode_name: String.t() | nil,
          extra_id: String.t() | nil,
          movie_id: String.t() | nil,
          episode_id: String.t() | nil,
          video_object_id: String.t() | nil,
          content_url: String.t(),
          start_position: number()
        }

  @typedoc """
  What a completed entry is remembered as (`Events.SessionEnded.completed`):
  the playable's kind and id, with an episode's numbers.
  """
  @type item ::
          {:movie | :video_object | :extra, String.t()}
          | {:episode, String.t(), integer() | nil, integer() | nil}

  @doc "The entry's completed-set item, or nil for an unattributed entry."
  @spec item(t()) :: item() | nil
  def item(%__MODULE__{extra_id: id}) when not is_nil(id), do: {:extra, id}
  def item(%__MODULE__{movie_id: id}) when not is_nil(id), do: {:movie, id}

  def item(%__MODULE__{episode_id: id} = entry) when not is_nil(id),
    do: {:episode, id, entry.season_number, entry.episode_number}

  def item(%__MODULE__{video_object_id: id}) when not is_nil(id), do: {:video_object, id}
  def item(%__MODULE__{}), do: nil

  @doc "Whether the entry names a playable the library knows."
  @spec attributed?(t()) :: boolean()
  def attributed?(%__MODULE__{} = entry), do: not is_nil(item(entry))

  @doc """
  An unattributed entry for `content_url` in the same chain as `entry`:
  the entity kept, every identity field cleared, the start at zero.
  """
  @spec unattributed(t(), String.t()) :: t()
  def unattributed(%__MODULE__{} = entry, content_url) do
    %__MODULE__{entity_id: entry.entity_id, entity_name: entry.entity_name, content_url: content_url}
  end
end
