defmodule MediaCentaurWeb.SettingsLive.Components do
  @moduledoc """
  Shared UI kit for the Settings page sections — the consistent row / card /
  field / status-dot treatments every section composes from. Function
  components imported by `SettingsLive` and the per-section render modules
  (`MediaCentaurWeb.SettingsLive.*`).
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Live.SettingsLive.{ConnectionTest, PathCheck}

  attr :label, :any,
    required: true,
    doc: "label content — accepts a string or a HEEx slot/AST. `:any` covers both."

  attr :description, :string, required: true
  attr :checked, :boolean, required: true
  attr :event, :string, required: true
  attr :event_value, :map, default: %{}, doc: "phx-value-* params map (string-keyed)."
  attr :color, :string, default: "info"

  def settings_row(assigns) do
    ~H"""
    <div
      class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg transition-colors duration-150 cursor-pointer hover:bg-base-content/[0.04]"
      data-nav-item
      tabindex="0"
      phx-click={@event}
      {phx_values(@event_value)}
    >
      <div>
        <span class="font-medium">{@label}</span>
        <p class="text-xs text-base-content/50 mt-0.5">{@description}</p>
      </div>
      <input
        type="checkbox"
        class={"toggle toggle-sm toggle-#{@color}"}
        checked={@checked}
        tabindex="-1"
      />
    </div>
    """
  end

  attr :label, :any,
    required: true,
    doc: "label content — accepts a string or a HEEx slot/AST. `:any` covers both."

  attr :description, :string, required: true

  attr :value_label, :string,
    required: true,
    doc: "the current value formatted for display, e.g. `\"115%\"`."

  attr :down_value, :any,
    required: true,
    doc: "absolute target one step down — already clamped by the value's owner."

  attr :up_value, :any,
    required: true,
    doc: "absolute target one step up — already clamped by the value's owner."

  attr :reset_value, :any, required: true, doc: "the default the Reset button returns to."
  attr :at_min, :boolean, required: true
  attr :at_max, :boolean, required: true
  attr :at_default, :boolean, required: true
  attr :event, :string, required: true

  @doc """
  A bounded-numeric stepper — the counterpart to `settings_row`'s toggle for a
  continuous setting. Renders −/+ buttons around the formatted value plus a
  Reset, all focusable nav items (keyboard/gamepad navigable). The component is
  a dumb renderer: every button carries a precomputed **absolute** target in
  `phx-value-choice`, so the arithmetic (step, clamp) stays with the value's
  owner and the event handler keeps idempotent set-to-value semantics. At a
  bound the button's target equals the current value (a no-op) and it reads
  `aria-disabled` — it deliberately stays clickable and focusable so the nav
  graph never shifts under focus. (The param is `choice`, not `value`: a
  `<button>` has a native `value` DOM property that LiveView merges into the
  payload and would clobber a `phx-value-value` with the element's empty
  string.)
  """
  def settings_stepper(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg">
      <div class="min-w-0">
        <span class="font-medium">{@label}</span>
        <p class="text-xs text-base-content/50 mt-0.5">{@description}</p>
      </div>
      <div class="flex items-center gap-1 shrink-0" role="group">
        <button
          type="button"
          data-nav-item
          tabindex="0"
          phx-click={@event}
          phx-value-choice={@down_value}
          aria-label="Decrease scale"
          aria-disabled={to_string(@at_min)}
          class={[stepper_button_class(), @at_min && "opacity-30", !@at_min && "cursor-pointer"]}
        >
          <.icon name="hero-minus-mini" class="size-4" />
        </button>
        <span class="w-12 text-center text-sm tabular-nums">{@value_label}</span>
        <button
          type="button"
          data-nav-item
          tabindex="0"
          phx-click={@event}
          phx-value-choice={@up_value}
          aria-label="Increase scale"
          aria-disabled={to_string(@at_max)}
          class={[stepper_button_class(), @at_max && "opacity-30", !@at_max && "cursor-pointer"]}
        >
          <.icon name="hero-plus-mini" class="size-4" />
        </button>
        <button
          type="button"
          data-nav-item
          tabindex="0"
          phx-click={@event}
          phx-value-choice={@reset_value}
          aria-label="Reset scale"
          aria-disabled={to_string(@at_default)}
          class={[
            "px-2.5 py-1 rounded-md text-sm transition-colors duration-150 text-base-content/60",
            @at_default && "opacity-30",
            !@at_default && "cursor-pointer hover:bg-base-content/[0.06]"
          ]}
        >
          Reset
        </button>
      </div>
    </div>
    """
  end

  defp stepper_button_class do
    "flex items-center justify-center size-7 rounded-md text-base-content/60 " <>
      "transition-colors duration-150 hover:bg-base-content/[0.06]"
  end

  # Card title row — one consistent treatment for every settings card:
  # muted, uppercase, with an optional right-aligned action.
  attr :title, :string, required: true
  slot :action

  def settings_card_header(assigns) do
    ~H"""
    <div class="flex items-baseline justify-between gap-4">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        {@title}
      </h3>
      <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
    </div>
    """
  end

  # One field inside a card: sentence-case label, optional terse description,
  # and a control. `:inline` keeps the control on the right; `:stacked` drops
  # a wide control full-width below.
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :layout, :atom, default: :inline, values: [:inline, :stacked]
  slot :inner_block, required: true

  def settings_field(assigns) do
    ~H"""
    <div class={[
      "py-3.5 border-t border-base-content/5 first:border-t-0 first:pt-0 last:pb-0",
      @layout == :inline && "flex items-start justify-between gap-6"
    ]}>
      <div class={["min-w-0", @layout == :inline && "max-w-[46ch]"]}>
        <div class="text-sm font-medium">{@label}</div>
        <p :if={@description} class="mt-0.5 text-xs text-base-content/50 max-w-[60ch]">
          {@description}
        </p>
      </div>
      <div class={[@layout == :stacked && "mt-2", @layout == :inline && "shrink-0 pt-0.5"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :configured, :boolean, required: true

  def status_dot(assigns) do
    ~H"""
    <span
      class={[
        "size-2 rounded-full shrink-0",
        if(@configured, do: "bg-success", else: "bg-base-content/20")
      ]}
      aria-label={if @configured, do: "Configured", else: "Not configured"}
      title={if @configured, do: "Configured", else: "Not configured"}
    >
    </span>
    """
  end

  attr :path, :any,
    required: true,
    doc:
      "path string OR a `{label, path}` tuple — `PathCheck.check/2` accepts both forms. `:any` covers the union."

  attr :kind, :atom, required: true, values: [:file, :directory, :executable]

  def path_status(assigns) do
    assigns = assign(assigns, :result, PathCheck.check(assigns.path, assigns.kind))

    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center size-3.5 shrink-0 relative top-px",
        PathCheck.ok?(@result) && "text-success",
        !PathCheck.ok?(@result) && "text-warning"
      ]}
      title={if PathCheck.ok?(@result), do: "Found at #{@path}", else: PathCheck.label(@result)}
      aria-label={PathCheck.label(@result)}
    >
      <.icon :if={PathCheck.ok?(@result)} name="hero-check-circle-mini" class="size-3.5" />
      <.icon
        :if={!PathCheck.ok?(@result)}
        name="hero-exclamation-triangle-mini"
        class="size-3.5"
      />
    </span>
    """
  end

  attr :test, :any,
    required: true,
    doc:
      "connection test result — `nil`, `%{status: :ok | :error, tested_at: DateTime.t(), ...}`, or atom shorthand. Heterogeneous shape; `:any` is intentional."

  attr :ok_label, :string, required: true
  attr :error_label, :string, required: true

  def connection_status(assigns) do
    status = if is_map(assigns.test), do: assigns.test.status
    age = if is_map(assigns.test), do: ConnectionTest.relative_age(assigns.test.tested_at)
    assigns = assign(assigns, status: status, age: age)

    ~H"""
    <div class="flex items-center gap-2 min-w-0 text-sm">
      <span class={[
        "size-2 rounded-full shrink-0",
        @status == :ok && "bg-success",
        @status == :error && "bg-error",
        is_nil(@status) && "bg-base-content/30"
      ]}>
      </span>
      <span class="min-w-0 truncate">
        <span class="text-base-content/70">
          {cond do
            @status == :ok -> @ok_label
            @status == :error -> @error_label
            true -> "Not tested"
          end}
        </span>
        <span :if={@age} class="text-base-content/40 text-xs">· {@age}</span>
      </span>
    </div>
    """
  end

  defp phx_values(map) when map_size(map) == 0, do: %{}

  defp phx_values(map) do
    # String keys avoid creating atoms at runtime — Phoenix accepts both.
    Map.new(map, fn {key, value} -> {"phx-value-#{key}", value} end)
  end
end
