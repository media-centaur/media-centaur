defmodule MediaCentaurWeb.Live.ArmGesture do
  @moduledoc """
  The arm gesture's state (MC0027 tier 2): one armed slot per LiveView and
  the one rule that clears it.

  A destructive button that takes the gesture sends **one** event. Its
  handler asks `press/3` whether this click arms or fires: the first click
  arms the gesture for its target, a second click on the same gesture and
  target fires, and a click on the same gesture for another target re-arms
  there. `Components.CoreComponents.armed_button/1` draws the button from
  `armed?/3`.

  Registered as an `on_mount` on the `:default` live session, so every page
  holds the slot in `:armed_gesture` and gets the rule without opting in:

    * **any other event disarms.** A `handle_event` hook clears the slot
      before the page's own handler runs, unless the event is the armed
      gesture's own. It is attached before any page's hooks, so it sees
      events a page's hook would halt (the title detail host's).
    * **navigation disarms.** A `handle_params` hook clears it on every
      patch, so leaving a section and coming back never finds a button one
      click from firing.

  PubSub messages do not disarm: a re-render the user did not cause is not
  a change of mind. Events handled by a LiveComponent (`phx-target`) do not
  reach the hook; no arm gesture lives in one.

  One gesture is armed at a time, which the rule already implies: arming a
  second gesture is an interaction with something else.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView

  @typedoc "Nothing armed, or the armed gesture's event and target."
  @type slot :: nil | {event :: String.t(), target :: term()}

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(:armed_gesture, nil)
     |> LiveView.attach_hook(:arm_gesture_events, :handle_event, &disarm_on_other_event/3)
     |> LiveView.attach_hook(:arm_gesture_navigation, :handle_params, &disarm_on_navigation/3)}
  end

  @doc """
  Presses the gesture `event` for `target` on the socket's slot. Returns
  `{:fire, socket}` when this is the confirming click, with the slot
  emptied, or `{:armed, socket}` when it armed.
  """
  @spec press(LiveView.Socket.t(), String.t(), term()) ::
          {:fire | :armed, LiveView.Socket.t()}
  def press(socket, event, target \\ nil) do
    {outcome, slot} = pressed(socket.assigns.armed_gesture, event, target)
    {outcome, assign(socket, :armed_gesture, slot)}
  end

  @doc "Empties the slot, for a handler that settles the gesture another way."
  @spec disarm(LiveView.Socket.t()) :: LiveView.Socket.t()
  def disarm(socket), do: assign(socket, :armed_gesture, nil)

  @doc "The pure step behind `press/3`: the outcome and the next slot."
  @spec pressed(slot(), String.t(), term()) :: {:fire | :armed, slot()}
  def pressed({event, target}, event, target), do: {:fire, nil}
  def pressed(_slot, event, target), do: {:armed, {event, target}}

  @doc "The slot after `event` passes the hook: kept for its own gesture, else empty."
  @spec after_event(slot(), String.t()) :: slot()
  def after_event({event, _target} = slot, event), do: slot
  def after_event(_slot, _event), do: nil

  @doc "True when `event` is armed for `target`."
  @spec armed?(slot(), String.t(), term()) :: boolean()
  def armed?(slot, event, target \\ nil), do: slot == {event, target}

  @doc """
  The target `event` is armed for, or `nil`. Given a list of events — one
  family of buttons, each sending its own — the target of whichever is armed.
  """
  @spec armed_target(slot(), String.t() | [String.t()]) :: term()
  def armed_target({event, target}, event), do: target

  def armed_target({armed_event, target}, events) when is_list(events),
    do: if(armed_event in events, do: target)

  def armed_target(_slot, _event), do: nil

  defp disarm_on_other_event(event, _params, socket) do
    {:cont, assign(socket, :armed_gesture, after_event(socket.assigns.armed_gesture, event))}
  end

  defp disarm_on_navigation(_params, _uri, socket), do: {:cont, disarm(socket)}
end
