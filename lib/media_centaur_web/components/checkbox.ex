defmodule MediaCentaurWeb.Components.Checkbox do
  @moduledoc """
  The house checkbox: a square that is ticked, partly ticked (a block
  whose rows are only some of them ticked) or empty, drawn in primary.

  Two forms of one drawing:

    * `checkbox/1` — a button of its own, a nav item; the plan modal's
      seasons and episodes, where the box is the control.
    * `checkbox_mark/1` — the square alone, inert; a row that is itself
      the control draws it (Review's bulk list, where pressing anywhere
      on the row ticks it). A button inside a button would be invalid
      markup and two click targets.

  Neither holds state: the caller owns the event and passes the state.
  """
  use MediaCentaurWeb, :html

  attr :state, :atom,
    required: true,
    values: [:checked, :indeterminate, :unchecked, :disabled],
    doc: "what the square shows; `:disabled` is drawn faint."

  attr :small, :boolean, default: false, doc: "16px instead of 18px — a nested row."
  attr :class, :any, default: nil, doc: "utilities for the square, e.g. a margin; a string or a list."

  @doc "The checkbox's square alone, inert — for a row that is itself the control."
  def checkbox_mark(assigns) do
    ~H"""
    <span
      class={[
        "flex-shrink-0 rounded border flex items-center justify-center transition-colors",
        @small && "w-4 h-4",
        !@small && "w-[18px] h-[18px]",
        @state in [:checked, :indeterminate] && "bg-primary/80 border-primary",
        @state == :unchecked && "border-base-content/30",
        @state == :disabled && "border-base-content/15",
        @class
      ]}
      aria-hidden="true"
    >
      <.icon :if={@state == :checked} name="hero-check-mini" class="size-3 text-base-100" />
      <.icon :if={@state == :indeterminate} name="hero-minus-mini" class="size-3 text-base-100" />
    </span>
    """
  end

  attr :state, :atom, required: true, values: [:checked, :indeterminate, :unchecked, :disabled]
  attr :small, :boolean, default: false

  attr :rest, :global,
    doc: "phx-click/phx-value-* passthrough — the checkbox is a dumb button; callers own the event."

  @doc "A checkbox that is its own control: a button and a nav item, disabled when `:disabled`."
  def checkbox(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "flex-shrink-0 cursor-pointer rounded",
        @state == :unchecked && "[&:hover>span]:border-base-content/60"
      ]}
      disabled={@state == :disabled}
      role="checkbox"
      aria-checked={aria_checked(@state)}
      data-nav-item
      tabindex="0"
      {@rest}
    >
      <.checkbox_mark state={@state} small={@small} />
    </button>
    """
  end

  defp aria_checked(:checked), do: "true"
  defp aria_checked(:indeterminate), do: "mixed"
  defp aria_checked(_state), do: "false"
end
