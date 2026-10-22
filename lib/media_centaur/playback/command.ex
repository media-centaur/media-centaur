defmodule MediaCentaur.Playback.Command do
  @moduledoc """
  What a reader of a viewing may ask of it, as one typed vocabulary, and
  the mpv command each one becomes.

  A remote player's keys go to the host's page, which sends one of these
  through `Playback.command/3`; the session renders it with `ipc/2` and
  sends it down its transport. The page never composes mpv IPC, and the
  session stays the only writer to the player.

    * `:toggle_pause`
    * `{:seek, seconds}` — relative, negative for back (a keyframe seek, as a key's)
    * `{:seek_to, seconds}` — absolute and exact, as a seekbar's
    * `:activate_prompt` — what the viewing's prompt offers (`Viewing.prompt/1`):
      a seek past the intro, or the next episode now
    * `{:select_track, :audio | :subtitle, id | :none}`

  A command is bounded to the file before it is rendered (`within/3`): a
  seek that would cross the end becomes an exact seek to one second short
  of the duration, so the file plays out and ends the way it always does —
  the prompt, the queued successor, `eof-reached`. mpv itself lands a seek
  past the end on the last frame, paused, and never reports the end
  (`keep-open`), which would leave the viewing open until the reader stops
  it; and a keyframe seek that close to the end snaps onto it, hence exact.
  """

  alias MediaCentaur.Playback.Viewing

  @type t ::
          :toggle_pause
          | {:seek, number()}
          | {:seek_to, number()}
          | :activate_prompt
          | {:select_track, :audio | :subtitle, integer() | :none}

  @doc "Whether a term is one of the vocabulary."
  @spec valid?(term()) :: boolean()
  def valid?(:toggle_pause), do: true
  def valid?({:seek, seconds}) when is_number(seconds), do: true
  def valid?({:seek_to, seconds}) when is_number(seconds), do: true
  def valid?(:activate_prompt), do: true
  def valid?({:select_track, kind, :none}) when kind in [:audio, :subtitle], do: true
  def valid?({:select_track, kind, id}) when kind in [:audio, :subtitle] and is_integer(id), do: true
  def valid?(_other), do: false

  @end_margin_seconds 1

  @doc """
  `command` bounded to the file at `position` of `duration`: a forward seek
  that would cross the end becomes an exact seek to `#{@end_margin_seconds}` s
  short of it, and one with nothing left becomes nil. An unknown duration
  (0, before mpv reports it) bounds nothing; every other command passes.
  """
  @spec within(t(), number(), number()) :: t() | nil
  def within({:seek, seconds}, position, duration) when seconds > 0 and duration > 0 do
    last = duration - @end_margin_seconds

    cond do
      position >= last -> nil
      position + seconds > last -> {:seek_to, last}
      true -> {:seek, seconds}
    end
  end

  def within(command, _position, _duration), do: command

  @doc "The mpv command for `command` given the viewing's current prompt; nil when there is nothing to send."
  @spec ipc(t(), Viewing.prompt()) :: list() | nil
  def ipc(:toggle_pause, _prompt), do: ["cycle", "pause"]
  def ipc({:seek, seconds}, _prompt), do: ["seek", seconds, "relative"]
  def ipc({:seek_to, seconds}, _prompt), do: ["seek", seconds, "absolute+exact"]
  def ipc(:activate_prompt, {:skip_intro, target}), do: ["seek", target, "absolute"]
  def ipc(:activate_prompt, :next_episode), do: ["playlist-next"]
  def ipc(:activate_prompt, {:next_episode_in, _seconds}), do: ["playlist-next"]
  def ipc(:activate_prompt, nil), do: nil
  def ipc({:select_track, :audio, id}, _prompt), do: ["set_property", "aid", track_value(id)]
  def ipc({:select_track, :subtitle, id}, _prompt), do: ["set_property", "sid", track_value(id)]

  defp track_value(:none), do: "no"
  defp track_value(id), do: id
end
