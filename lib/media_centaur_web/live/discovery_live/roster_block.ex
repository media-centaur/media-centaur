defmodule MediaCentaurWeb.DiscoveryLive.RosterBlock do
  @moduledoc """
  The Friends tab's roster block: the keys whose recommendations this
  install reads, each under the nickname given here, with an add form and
  a per-row remove. Iteration-phase component (lives with the LiveView,
  no story yet — spec decision 11). Events bubble to `DiscoveryLive`:
  `add_friend`, `remove_friend`.
  """

  use MediaCentaurWeb, :html

  alias MediaCentaur.Social

  attr :friends, :list, required: true, doc: "`Friend.t()` by nickname"

  def roster_block(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4" data-component="roster-block">
      <div class="space-y-1">
        <h2 class="text-sm font-semibold">Friends</h2>
        <p class="text-xs text-base-content/50">
          People whose recommendations you read. Add a friend with the key they give you; the name is only for you.
        </p>
      </div>

      <ul :if={@friends != []} class="space-y-2">
        <li
          :for={friend <- @friends}
          id={dom_id(friend.pubkey)}
          class="flex items-center gap-3 rounded-md bg-base-content/5 px-3 py-2"
        >
          <span class="min-w-0 flex-1 truncate text-sm font-medium">{friend.nickname}</span>
          <code class="shrink-0 text-xs text-base-content/50">{short_npub(friend.pubkey)}</code>
          <.button
            variant="dismiss"
            size="xs"
            class="shrink-0"
            phx-click="remove_friend"
            phx-value-pubkey={friend.pubkey}
          >
            Remove
          </.button>
        </li>
      </ul>

      <form id="add-friend-form" phx-submit="add_friend" class="flex items-center gap-2">
        <input
          type="text"
          name="key"
          placeholder="npub1…"
          class="library-filter min-w-0 flex-1"
          autocomplete="off"
        />
        <%!-- The name field is sized by flex-basis, not width: `.library-filter`
        collapses its `width` while empty and unfocused (the library search
        idiom), and only a set basis keeps a fixed field open. --%>
        <input
          type="text"
          name="nickname"
          placeholder="Name"
          class="library-filter basis-40 grow-0 shrink-0"
          autocomplete="off"
        />
        <.button type="submit" variant="neutral" size="sm">Add friend</.button>
      </form>
    </section>
    """
  end

  @doc "A DOM id for a friend's public key."
  @spec dom_id(String.t()) :: String.t()
  def dom_id(pubkey), do: "friend-" <> String.slice(pubkey, 0, 8)

  @doc "The npub, elided in the middle — enough to compare against what a friend told you."
  @spec short_npub(String.t()) :: String.t()
  def short_npub(pubkey) do
    npub = Social.to_npub(pubkey)
    String.slice(npub, 0, 9) <> "…" <> String.slice(npub, -4..-1//1)
  end
end
