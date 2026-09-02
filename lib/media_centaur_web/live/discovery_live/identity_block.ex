defmodule MediaCentaurWeb.DiscoveryLive.IdentityBlock do
  @moduledoc """
  The Social tab's identity block: this install's npub with a copy
  control, and a disclosure holding the secret key (reveal + copy) and
  the import form. The import textarea renders `import_draft`, so the
  arming click keeps what was pasted and a finished import clears it.
  Iteration-phase component (lives with the LiveView,
  no story yet — spec decision 11). Events bubble to `DiscoveryLive`:
  `reveal_nsec`, `hide_nsec`, `import_nsec`.
  """

  use MediaCentaurWeb, :html

  attr :npub, :string, required: true
  attr :nsec_revealed, :string, default: nil, doc: "the nsec while revealed; nil hides it"
  attr :import_armed?, :boolean, required: true
  attr :import_draft, :string, default: "", doc: "the pasted nsec while the replace is armed"

  def identity_block(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4" data-component="identity-block">
      <div class="space-y-1">
        <h2 class="text-sm font-semibold">Your identity</h2>
        <p class="text-xs text-base-content/50">
          Friends add you by this key. Your recommendations are visible to anyone who can read the relays you configure.
        </p>
      </div>

      <div class="flex items-center gap-3">
        <code
          id="identity-npub"
          class="min-w-0 flex-1 truncate rounded-md bg-base-content/5 px-3 py-2 text-xs"
        >
          {@npub}
        </code>
        <.button
          id="copy-npub"
          variant="dismiss"
          size="xs"
          class="shrink-0"
          phx-hook="CopyButton"
          data-copy-text={@npub}
        >
          Copy
        </.button>
      </div>

      <details class="release-notes-disclosure">
        <summary class="cursor-pointer select-none text-xs text-base-content/50 inline-flex items-center gap-1.5">
          <.icon name="hero-chevron-right-mini" class="size-4 disclosure-caret" />
          <span>Secret key</span>
        </summary>
        <div class="mt-3 ml-5 space-y-4 border-l border-base-content/10 pl-4 text-sm">
          <p class="text-xs text-base-content/60">
            This key is your identity. Anyone who has it can publish as you. Keep it somewhere safe; it is the only way to move this identity to another machine.
          </p>

          <div :if={is_nil(@nsec_revealed)}>
            <.button id="reveal-nsec" variant="neutral" size="sm" phx-click="reveal_nsec">
              Show secret key
            </.button>
          </div>
          <div :if={@nsec_revealed} class="flex items-center gap-3">
            <code
              id="identity-nsec"
              class="min-w-0 flex-1 truncate rounded-md bg-base-content/5 px-3 py-2 text-xs"
            >
              {@nsec_revealed}
            </code>
            <.button
              id="copy-nsec"
              variant="dismiss"
              size="xs"
              class="shrink-0"
              phx-hook="CopyButton"
              data-copy-text={@nsec_revealed}
            >
              Copy
            </.button>
            <.button variant="dismiss" size="xs" class="shrink-0" phx-click="hide_nsec">Hide</.button>
          </div>

          <form id="import-nsec-form" phx-submit="import_nsec" class="space-y-2">
            <label for="import-nsec" class="block text-xs font-medium">Import a secret key</label>
            <textarea
              id="import-nsec"
              name="nsec"
              rows="2"
              placeholder="nsec1…"
              class="textarea textarea-bordered w-full font-mono text-xs"
            >{@import_draft}</textarea>
            <.button
              id="import-nsec-submit"
              type="submit"
              variant={if @import_armed?, do: "danger", else: "neutral"}
              size="sm"
            >
              {if @import_armed?, do: "Click again to replace", else: "Replace identity"}
            </.button>
          </form>
        </div>
      </details>
    </section>
    """
  end
end
