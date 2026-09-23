defmodule MediaCentaurWeb.Components.Settings.ConnectionRow do
  @moduledoc """
  The readout for one external endpoint (UIDR-041 §1): a state dot, the
  name with an optional kind tag, a detail line (the address as a link to
  the endpoint's own web UI, then the credential summary or a
  description), the state word with the test's age, and the actions the
  host passes in. When `editing` the host's `edit` slot renders beneath,
  indented under a hairline. The component draws; `SettingsLive` and
  `SettingsLive.ConnectionState` decide.

  Rows are `<li>`s; the host renders the `<ul>`.

  In a narrow card the name block keeps a 16rem measure and the state
  word and actions drop together to a second line, right-aligned, so the
  actions stay on the card's edge whether or not the row fits on one line.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaurWeb.Live.SettingsLive.ConnectionTest

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :kind, :string, default: nil, doc: "protocol tag beside the name: torrent, usenet."
  attr :monospace_name, :boolean, default: false, doc: "relays: the name is a URL."

  attr :state, :atom,
    required: true,
    values: [:not_configured, :not_tested, :pending, :ok, :error, :detected]

  attr :state_label, :string, required: true

  attr :tested_at, :any,
    default: nil,
    doc: "`DateTime` of the persisted test, or nil; rendered as a relative age."

  attr :address, :string, default: nil, doc: "linked to the endpoint's web UI."
  attr :detail, :string, default: nil, doc: "credential summary, description, or last error."
  attr :editing, :boolean, default: false
  slot :actions
  slot :edit

  def connection_row(assigns) do
    assigns = assign(assigns, :age, assigns.tested_at && ConnectionTest.relative_age(assigns.tested_at))

    ~H"""
    <li id={@id} class="py-3 border-t border-base-content/5 first:border-t-0 first:pt-0 last:pb-0">
      <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
        <span class={["size-2 rounded-full shrink-0", dot_class(@state)]} aria-hidden="true"></span>
        <div class="min-w-0 grow basis-64">
          <div class="flex items-baseline gap-2">
            <span class={["text-sm font-medium truncate", @monospace_name && "font-mono"]}>
              {@name}
            </span>
            <span :if={@kind} class="text-xs text-base-content/55">{@kind}</span>
          </div>
          <div :if={@editing} class="text-xs text-base-content/60">
            Editing. Saving clears the last test; test again afterwards.
          </div>
          <div
            :if={!@editing && (@address || @detail)}
            class="text-xs text-base-content/60 flex items-center gap-1.5 min-w-0"
          >
            <a
              :if={@address}
              href={@address}
              target="_blank"
              rel="noopener"
              class="font-mono truncate inline-flex items-center gap-1 hover:text-base-content"
              data-nav-item
              tabindex="0"
            >
              {@address} <.icon name="hero-arrow-top-right-on-square-mini" class="size-3" />
            </a>
            <span :if={@address && @detail}>·</span>
            <span :if={@detail} class="truncate" title={@detail}>{@detail}</span>
          </div>
        </div>
        <div class="ml-auto min-w-0 flex flex-wrap items-center justify-end gap-x-4 gap-y-1.5">
          <div class={[
            "text-sm text-right inline-flex flex-wrap items-center justify-end gap-x-2",
            state_text_class(@state)
          ]}>
            <span :if={@state == :pending} class="loading loading-spinner loading-xs"></span>
            {@state_label}
            <span :if={@age} class="text-xs text-base-content/55 whitespace-nowrap">
              · tested {@age}
            </span>
          </div>
          <div :if={!@editing && @actions != []} class="flex gap-1 shrink-0">
            {render_slot(@actions)}
          </div>
        </div>
      </div>
      <div :if={@editing} class="mt-3 ml-6 pl-4 border-l border-base-content/10">
        {render_slot(@edit)}
      </div>
    </li>
    """
  end

  defp dot_class(:ok), do: "bg-success"
  defp dot_class(:error), do: "bg-error"
  defp dot_class(:not_configured), do: "bg-base-content/20"
  defp dot_class(_neutral), do: "bg-base-content/30"

  defp state_text_class(:not_configured), do: "text-base-content/55"
  defp state_text_class(_state), do: "text-base-content/70"
end
