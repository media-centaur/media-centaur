defmodule MediaCentaurWeb.Live.ViewingAware.Logic do
  @moduledoc """
  The pure half of `Live.ViewingAware` (ADR-030): the page's event
  payloads as `Playback.Command`s, and the viewing layer's own state —
  the viewing, whether the bar is on screen, whether the track menu is
  open, the timer that hides the bar.
  """

  alias MediaCentaur.Playback.Viewing

  @typedoc "The viewing layer's state: nil when the player has no viewing."
  @type layer :: %{
          viewing: Viewing.t(),
          bar_shown?: boolean(),
          menu_open?: boolean(),
          bar_timer: reference() | nil
        }

  @doc "The layer for the first session on `player_id` in a `Sessions.list/0` snapshot, or nil."
  @spec initial([map()], String.t()) :: layer() | nil
  def initial(sessions, player_id) do
    case Enum.find(sessions, &(&1.player == player_id and &1.now_playing != nil)) do
      nil -> nil
      session -> new(session.now_playing)
    end
  end

  @doc "A fresh layer for a viewing: no timer, the menu closed; the bar shows only if paused."
  @spec new(Viewing.t()) :: layer()
  def new(%Viewing{} = viewing),
    do: %{viewing: viewing, bar_shown?: bar_shown?(viewing, false), menu_open?: false, bar_timer: nil}

  @doc "The layer with a newer viewing; the menu and the timer stay, the bar follows the pause and the timer."
  @spec update(layer() | nil, Viewing.t()) :: layer()
  def update(nil, viewing), do: new(viewing)

  def update(layer, viewing),
    do: %{layer | viewing: viewing, bar_shown?: bar_shown?(viewing, layer.bar_timer != nil)}

  @doc "The layer after a key: the bar shows and `timer` will hide it."
  @spec bar_held(layer(), reference()) :: layer()
  def bar_held(layer, timer), do: %{layer | bar_shown?: true, bar_timer: timer}

  @doc "The layer when the timer fires: the bar hides unless paused."
  @spec bar_released(layer()) :: layer()
  def bar_released(layer), do: %{layer | bar_shown?: bar_shown?(layer.viewing, false), bar_timer: nil}

  @doc "Whether the bar is on screen: while paused, or while the show timer runs after a key."
  @spec bar_shown?(Viewing.t(), boolean()) :: boolean()
  def bar_shown?(%Viewing{state: :paused}, _timer_running?), do: true
  def bar_shown?(_viewing, timer_running?), do: timer_running?

  @doc "`viewing_command`'s payload as a command: pause, a relative seek, or the prompt."
  @spec command_from_params(map()) :: {:ok, MediaCentaur.Playback.Command.t()} | :error
  def command_from_params(%{"command" => "toggle_pause"}), do: {:ok, :toggle_pause}
  def command_from_params(%{"command" => "prompt"}), do: {:ok, :activate_prompt}

  def command_from_params(%{"command" => "seek", "seconds" => seconds}) do
    case integer(seconds) do
      {:ok, n} -> {:ok, {:seek, n}}
      :error -> :error
    end
  end

  def command_from_params(_params), do: :error

  @doc "`viewing_track`'s payload as a track command: a kind and an id, or `none`."
  @spec track_from_params(map()) :: {:ok, MediaCentaur.Playback.Command.t()} | :error
  def track_from_params(%{"kind" => kind, "id" => id}) when kind in ["audio", "subtitle"] do
    case {id, integer(id)} do
      {"none", _} -> {:ok, {:select_track, String.to_existing_atom(kind), :none}}
      {_, {:ok, n}} -> {:ok, {:select_track, String.to_existing_atom(kind), n}}
      _other -> :error
    end
  end

  def track_from_params(_params), do: :error

  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      _other -> :error
    end
  end

  defp integer(_value), do: :error
end
