defmodule MediaCentaur.Playback.Command do
  @moduledoc """
  What a reader of a viewing may ask of it, as one typed vocabulary, and
  the mpv command each one becomes.

  A remote player's keys go to the host's page, which sends one of these
  through `Playback.command/3`; the session renders it with `ipc/2` and
  sends it down its transport. The page never composes mpv IPC, and the
  session stays the only writer to the player.

    * `:toggle_pause`
    * `{:seek, seconds}` — relative, negative for back
    * `:activate_prompt` — what the viewing's prompt offers (`Viewing.prompt/1`):
      a seek past the intro, or the next episode now
    * `{:select_track, :audio | :subtitle, id | :none}`
  """

  alias MediaCentaur.Playback.Viewing

  @type t ::
          :toggle_pause
          | {:seek, number()}
          | :activate_prompt
          | {:select_track, :audio | :subtitle, integer() | :none}

  @doc "Whether a term is one of the vocabulary."
  @spec valid?(term()) :: boolean()
  def valid?(:toggle_pause), do: true
  def valid?({:seek, seconds}) when is_number(seconds), do: true
  def valid?(:activate_prompt), do: true
  def valid?({:select_track, kind, :none}) when kind in [:audio, :subtitle], do: true
  def valid?({:select_track, kind, id}) when kind in [:audio, :subtitle] and is_integer(id), do: true
  def valid?(_other), do: false

  @doc "The mpv command for `command` given the viewing's current prompt; nil when there is nothing to send."
  @spec ipc(t(), Viewing.prompt()) :: list() | nil
  def ipc(:toggle_pause, _prompt), do: ["cycle", "pause"]
  def ipc({:seek, seconds}, _prompt), do: ["seek", seconds, "relative"]
  def ipc(:activate_prompt, {:skip_intro, target}), do: ["seek", target, "absolute"]
  def ipc(:activate_prompt, :next_episode), do: ["playlist-next"]
  def ipc(:activate_prompt, {:next_episode_in, _seconds}), do: ["playlist-next"]
  def ipc(:activate_prompt, nil), do: nil
  def ipc({:select_track, :audio, id}, _prompt), do: ["set_property", "aid", track_value(id)]
  def ipc({:select_track, :subtitle, id}, _prompt), do: ["set_property", "sid", track_value(id)]

  defp track_value(:none), do: "no"
  defp track_value(id), do: id
end
