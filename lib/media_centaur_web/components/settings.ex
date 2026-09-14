defmodule MediaCentaurWeb.Components.Settings do
  @moduledoc """
  The Settings kit (UIDR-041): the components every Settings section
  composes from. A section is cards of rows. `settings_card/1` is the
  card; `settings_row/1` (toggle), `settings_stepper/1`,
  `settings_choice/1`, `settings_text_row/1` and `settings_select_row/1`
  are the rows, each saving on the act; `settings_list/1` is a
  string-list setting; `settings_field/1` and `settings_input/1` are the
  label/control/help unit and the house input inside a connection row's
  edit form; `settings_disclosure/1` hides rare content; `path_status/1`
  is the glyph beside a path label. The connection row lives in
  `MediaCentaurWeb.Components.Settings.ConnectionRow`.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Live.SettingsLive.PathCheck
  alias Phoenix.LiveView.JS

  attr :id, :string, default: nil

  attr :label, :any,
    required: true,
    doc: "label content — accepts a string or a HEEx slot/AST. `:any` covers both."

  attr :description, :string, required: true
  attr :checked, :boolean, required: true
  attr :event, :string, required: true
  attr :event_value, :map, default: %{}, doc: "phx-value-* params map (string-keyed)."

  attr :disabled?, :boolean,
    default: false,
    doc:
      "no click and `aria-disabled`; the description says why. The row keeps its place so the nav graph never shifts."

  @doc "A boolean setting: label and description on the left, the toggle on the right, saved on click."
  def settings_row(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg transition-colors duration-150",
        if(@disabled?, do: "opacity-60", else: "cursor-pointer hover:bg-base-content/[0.04]")
      ]}
      data-nav-item
      tabindex="0"
      aria-disabled={@disabled? && "true"}
      phx-click={!@disabled? && @event}
      {phx_values(if(@disabled?, do: %{}, else: @event_value))}
    >
      <div>
        <span class="font-medium">{@label}</span>
        <p class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <input type="checkbox" class="toggle toggle-sm toggle-info" checked={@checked} tabindex="-1" />
    </div>
    """
  end

  attr :id, :string, default: nil

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
  attr :event_value, :map, default: %{}, doc: "extra phx-value-* params on every button (string-keyed)."

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
    <div id={@id} class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg">
      <div class="min-w-0">
        <span class="font-medium">{@label}</span>
        <p class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <div class="flex items-center gap-1 shrink-0" role="group">
        <button
          type="button"
          data-nav-item
          tabindex="0"
          phx-click={@event}
          phx-value-choice={@down_value}
          {phx_values(@event_value)}
          aria-label={"Decrease #{@label}"}
          aria-disabled={to_string(@at_min)}
          class={[stepper_button_class(), @at_min && "opacity-30", !@at_min && "cursor-pointer"]}
        >
          <.icon name="hero-minus-mini" class="size-4" />
        </button>
        <span class="min-w-12 px-1 text-center text-sm tabular-nums whitespace-nowrap">{@value_label}</span>
        <button
          type="button"
          data-nav-item
          tabindex="0"
          phx-click={@event}
          phx-value-choice={@up_value}
          {phx_values(@event_value)}
          aria-label={"Increase #{@label}"}
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
          {phx_values(@event_value)}
          aria-label={"Reset #{@label}"}
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

  # One field inside a card: sentence-case label, optional terse description,
  # and a control. `:inline` keeps the control on the right; `:stacked` drops
  # a wide control full-width below.
  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :layout, :atom, default: :inline, values: [:inline, :stacked]
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def settings_field(assigns) do
    ~H"""
    <div class={[
      "py-3.5 border-t border-base-content/5 first:border-t-0 first:pt-0 last:pb-0",
      @layout == :inline && "flex items-start justify-between gap-6",
      @class
    ]}>
      <div class={["min-w-0", @layout == :inline && "max-w-[46ch]"]}>
        <div class="text-sm font-medium">{@label}</div>
        <p :if={@description} class="mt-0.5 text-xs text-base-content/55 max-w-[60ch]">
          {@description}
        </p>
      </div>
      <div class={[@layout == :stacked && "mt-2", @layout == :inline && "shrink-0 pt-0.5"]}>
        {render_slot(@inner_block)}
      </div>
    </div>
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

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, doc: "an `id` or data attribute for the card element, e.g. a test anchor."
  slot :action
  slot :inner_block, required: true

  @doc "One card in a settings section (UIDR-041 §3): uppercase title, optional description and action, a body of rows."
  def settings_card(assigns) do
    ~H"""
    <div class={["glass-surface rounded-xl p-5 space-y-3", @class]} {@rest}>
      <div class="flex items-baseline justify-between gap-4">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">{@title}</h3>
        <div :if={@action != []} class="shrink-0">{render_slot(@action)}</div>
      </div>
      <p :if={@description} class="text-xs text-base-content/55 max-w-[60ch]">{@description}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :label, :any,
    required: true,
    doc: "label content — accepts a string or a HEEx slot/AST. `:any` covers both."

  attr :description, :string, default: nil
  attr :options, :list, required: true, doc: "`[{value, label}]`, at most four."

  attr :selected, :any,
    required: true,
    doc: "the current option value — a string or atom, whatever the owner stores. Compared with `==`."

  attr :event, :string, required: true
  attr :event_value, :map, default: %{}, doc: "extra `phx-value-*` params (string keys)."
  attr :id, :string, default: nil

  @doc """
  A pick-one-of-N row on the house segmented pill (UIDR-041 §2). Each
  option is a nav item; the chosen one carries `aria-pressed`. Clicking
  pushes `@event` with `choice` set to the option value (never `value`:
  a button's native `value` property would clobber it, MC0021).
  """
  def settings_choice(assigns) do
    ~H"""
    <div class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg">
      <div class="min-w-0">
        <span class="font-medium">{@label}</span>
        <p :if={@description} class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <div
        id={@id}
        class="tabs tabs-boxed segmented-control w-fit shrink-0"
        role="group"
        aria-label={@label}
      >
        <button
          :for={{value, label} <- @options}
          type="button"
          class="tab text-sm"
          phx-click={@event}
          phx-value-choice={value}
          {phx_values(@event_value)}
          aria-pressed={to_string(value == @selected)}
          data-nav-item
          tabindex="0"
        >
          {label}
        </button>
      </div>
    </div>
    """
  end

  attr :type, :string, default: "text"
  attr :name, :string, required: true

  attr :value, :any,
    default: nil,
    doc: "the current value — string, number or nil; rendered as the input's value."

  attr :placeholder, :string, default: nil
  attr :mono, :boolean, default: false
  attr :autofocus, :boolean, default: false, doc: "focus on mount — the first field of an edit form."
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(autocomplete list phx-blur phx-keydown phx-key phx-value-name min max step),
    doc: "input attributes the row kinds bind: autocomplete, the blur/keydown events, number bounds."

  @doc "The house text input (UIDR-041 §31): bordered, full width, monospace for paths and keys, a nav item."
  def settings_input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      phx-mounted={@autofocus && JS.focus()}
      class={["input input-bordered w-full text-sm", @mono && "font-mono", @class]}
      data-nav-item
      tabindex="0"
      {@rest}
    />
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :name, :string, required: true
  attr :value, :any, default: nil, doc: "the current value — string, number or nil."
  attr :placeholder, :string, default: nil

  attr :event, :string,
    required: true,
    doc: ~s(pushed with `%{"name" => name, "value" => typed}` on Enter and on blur.)

  attr :mono, :boolean, default: false
  attr :id, :string, default: nil
  slot :label_suffix, doc: "a glyph beside the label, e.g. `path_status`."

  @doc "A free-text setting that commits on Enter or blur (UIDR-041 §2, §30). One payload shape, no form."
  def settings_text_row(assigns) do
    ~H"""
    <div id={@id} class="py-2.5 px-3.5 space-y-1.5">
      <div class="flex items-center gap-1.5">
        <span class="font-medium">{@label}</span>
        {render_slot(@label_suffix)}
      </div>
      <p :if={@description} class="text-xs text-base-content/55">{@description}</p>
      <.settings_input
        name={@name}
        value={@value}
        placeholder={@placeholder}
        mono={@mono}
        phx-blur={@event}
        phx-keydown={@event}
        phx-key="Enter"
        phx-value-name={@name}
      />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :name, :string, required: true
  attr :options, :list, required: true, doc: "`[{value, label}]`, more than four."

  attr :selected, :any,
    required: true,
    doc: "the current option value — a string or atom, whatever the owner stores. Compared with `==`."

  attr :event, :string, required: true, doc: "pushed on change with `%{name => value}`."
  attr :id, :string, default: nil

  @doc "An enum too wide for the pill: a native select on the right, saving on change (UIDR-041 §2)."
  def settings_select_row(assigns) do
    ~H"""
    <form
      id={@id}
      phx-change={@event}
      class="flex items-center justify-between py-2.5 px-3.5 gap-4 rounded-lg"
    >
      <div class="min-w-0">
        <span class="font-medium">{@label}</span>
        <p :if={@description} class="text-xs text-base-content/55 mt-0.5">{@description}</p>
      </div>
      <select
        name={@name}
        class="select select-bordered select-sm shrink-0 text-sm"
        data-nav-item
        tabindex="0"
      >
        <option :for={{value, label} <- @options} value={value} selected={value == @selected}>
          {label}
        </option>
      </select>
    </form>
    """
  end

  attr :id, :string, default: nil
  attr :items, :list, required: true, doc: "the current entries, strings."

  attr :remove_event, :string,
    required: true,
    doc: "pushed with `phx-value-item` = the entry, plus `event_value`."

  attr :add_event, :string, required: true, doc: "the inline form's submit; the input is named `item`."

  attr :event_value, :map,
    default: %{},
    doc: "extra `phx-value-*` on Remove and hidden inputs on the add form, e.g. the config key."

  attr :placeholder, :string, default: nil
  attr :add_label, :string, default: "Add"
  attr :mono, :boolean, default: false
  attr :error, :string, default: nil, doc: "why the last add was refused; shown under the form."

  attr :change_event, :string,
    default: nil,
    doc:
      "when set, the add form validates on change with `%{\"item\" => typed}` and the input is controlled by `value`."

  attr :value, :string,
    default: nil,
    doc: "the add input's current text when `change_event` controls it."

  attr :add_disabled, :boolean, default: false, doc: "Add is inert while the typed entry is invalid."

  attr :truncate_left, :boolean,
    default: false,
    doc: "entries are file paths: keep the filename visible and elide the prefix."

  @doc "A string-list setting (UIDR-041 §32): one row per entry with Remove, an inline input with Add, an optional error line."
  def settings_list(assigns) do
    ~H"""
    <div id={@id} class="space-y-2">
      <ul :if={@items != []} class="space-y-2">
        <li
          :for={item <- @items}
          class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2"
        >
          <span
            class={[
              "min-w-0 flex-1 text-sm",
              @truncate_left && "truncate-left",
              !@truncate_left && "truncate",
              @mono && "font-mono"
            ]}
            title={item}
          >
            <bdo :if={@truncate_left} dir="ltr">{item}</bdo>
            <%= if !@truncate_left do %>
              {item}
            <% end %>
          </span>
          <.button
            variant="dismiss"
            size="xs"
            class="shrink-0"
            phx-click={@remove_event}
            phx-value-item={item}
            {phx_values(@event_value)}
            data-nav-item
            tabindex="0"
          >
            Remove
          </.button>
        </li>
      </ul>
      <form
        id={@id && "#{@id}-add"}
        phx-submit={@add_event}
        phx-change={@change_event}
        class="flex items-center gap-2"
      >
        <input :for={{key, value} <- @event_value} type="hidden" name={key} value={value} />
        <.settings_input
          name="item"
          value={@value}
          placeholder={@placeholder}
          mono={@mono}
          autocomplete="off"
          class="min-w-0 flex-1"
        />
        <.button
          type="submit"
          variant="neutral"
          size="sm"
          disabled={@add_disabled}
          data-nav-item
          tabindex="0"
        >
          {@add_label}
        </.button>
      </form>
      <p :if={@error} class="text-xs text-error">{@error}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :open, :boolean, default: false
  attr :id, :string, default: nil
  slot :inner_block, required: true

  @doc "Rare content behind a caret and a label (UIDR-041): the secret key, service details."
  def settings_disclosure(assigns) do
    ~H"""
    <details id={@id} class="settings-disclosure" open={@open}>
      <summary
        class="cursor-pointer select-none text-xs text-base-content/55 inline-flex items-center gap-1.5"
        data-nav-item
        tabindex="0"
      >
        <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
        <span>{@label}</span>
      </summary>
      <div class="mt-3 ml-5 space-y-4 border-l border-base-content/10 pl-4 text-sm">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  defp phx_values(map) when map_size(map) == 0, do: %{}

  defp phx_values(map) do
    # String keys avoid creating atoms at runtime — Phoenix accepts both.
    Map.new(map, fn {key, value} -> {"phx-value-#{key}", value} end)
  end
end
