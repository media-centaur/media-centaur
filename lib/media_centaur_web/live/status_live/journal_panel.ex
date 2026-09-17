defmodule MediaCentaurWeb.StatusLive.JournalPanel do
  @moduledoc """
  When the Status page's systemd-journal panel is open, and what the page owes
  `MediaCentaur.Console` on each transition.

  The journal tail is refcounted: `MediaCentaur.Console.JournalSource` runs
  `journalctl -f` only while at least one subscriber is listening. So the page
  subscribes when the reader expands the panel — not when the System drill-in
  opens, which would spawn the process for a passer-by — and it has to
  unsubscribe again on every path that takes the panel away, including
  navigating out of the drill-in. A missed unsubscribe leaves the subprocess
  running for the life of the VM.

  Pure view-model (ADR-030); `MediaCentaurWeb.StatusLive` makes the calls.
  """

  @typedoc "Whether the panel is expanded."
  @type open :: boolean()

  @typedoc "The `Console` call a transition owes."
  @type action :: :subscribe | :unsubscribe | :none

  @doc """
  Whether a panel currently `open?` is still open on `subsystem`'s drill-in.

  The journal is the System subsystem's: every other drill-in, and the closed
  board (`nil`), takes it away.
  """
  @spec open_on?(open(), atom() | nil) :: open()
  def open_on?(open?, subsystem), do: open? and subsystem == :system

  @doc "The `Console` call a move from `was` to `now` owes."
  @spec action(open(), open()) :: action()
  def action(false, true), do: :subscribe
  def action(true, false), do: :unsubscribe
  def action(_was, _now), do: :none
end
