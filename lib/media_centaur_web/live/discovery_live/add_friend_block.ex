defmodule MediaCentaurWeb.DiscoveryLive.AddFriendBlock do
  @moduledoc """
  The Friends tab's add-friend form: a key and, if the reader likes, the
  name it goes under here (UIDR-047: the optional override). Iteration-phase
  component (lives with the LiveView, no story yet — spec decision 11).
  `add_friend` bubbles to `DiscoveryLive`.
  """

  use MediaCentaurWeb, :html

  def add_friend_block(assigns) do
    ~H"""
    <section class="glass-surface rounded-xl p-5 space-y-4" data-component="add-friend-block">
      <div class="space-y-1">
        <h2 class="text-sm font-semibold">Add a friend</h2>
        <p class="text-xs text-base-content/55">
          Paste the key they give you. A name is optional and only you see it; without one you see the name they publish, or Unnamed.
        </p>
      </div>

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
          name="name"
          placeholder="Name (optional)"
          class="library-filter basis-40 grow-0 shrink-0"
          autocomplete="off"
        />
        <.button type="submit" variant="neutral" size="sm">Add friend</.button>
      </form>
    </section>
    """
  end
end
