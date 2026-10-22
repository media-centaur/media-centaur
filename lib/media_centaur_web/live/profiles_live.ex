defmodule MediaCentaurWeb.ProfilesLive do
  @moduledoc """
  The picker at `/profiles` (UIDR-053): "Who's watching?" over a tile
  per profile and, under the cap, the add tile, which opens the name
  field in its place; `adding?` is that one open state. A profile tile
  is a plain form posting to `ProfileController.activate/2` with
  `return_to`, since the session cookie is the controller's to write;
  the input system activates its button like any other on SELECT. On a
  switch the active profile's tile is marked current.

  One surface, two situations. At the door — a session with no active
  profile — it is full-screen: there is no one to show in the shell and
  nowhere else to go. On a switch — an active profile exists — it is a
  page of the shell, the switcher entry current and the sidebar the way
  out. `Live.ProfileAware` tells them apart: the picker is the one view
  it mounts with `:profile` nil instead of redirecting, and it owns
  `:profiles`, so a profile added from Settings shows at once.
  """

  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.Settings, only: [settings_input: 1]

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Components.ProfileTile
  alias MediaCentaurWeb.ProfileController.ReturnTo
  alias MediaCentaurWeb.ProfileWords

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Who's watching?", return_to: "/", adding?: false, add_error: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, return_to: ReturnTo.local_path(params["return_to"]))}
  end

  @impl true
  def handle_event("open_add", _params, socket),
    do: {:noreply, assign(socket, adding?: true, add_error: nil)}

  def handle_event("cancel_add", _params, socket),
    do: {:noreply, assign(socket, adding?: false, add_error: nil)}

  def handle_event("add_profile", %{"name" => name}, socket) do
    case Profiles.add(name) do
      {:ok, _profile} -> {:noreply, assign(socket, adding?: false, add_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, add_error: ProfileWords.error(reason))}
    end
  end

  @impl true
  def render(%{profile: nil} = assigns) do
    ~H"""
    <Layouts.input_system_root class="relative min-h-viewport">
      <div class="page-side-dim page-side-dim-calm" aria-hidden="true"></div>
      <.picker
        profiles={@profiles}
        return_to={@return_to}
        adding?={@adding?}
        add_error={@add_error}
        class="min-h-viewport"
      />
    </Layouts.input_system_root>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      profile={@profile}
      profiles={@profiles}
      viewing_layer={assigns[:viewing_layer]}
      show_social={@show_social}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/profiles"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <%!-- The shell's main pads 1.5rem top and bottom; the rest of the
            viewport centres the question as the door does. --%>
      <.picker
        profiles={@profiles}
        current_id={@profile.id}
        return_to={@return_to}
        adding?={@adding?}
        add_error={@add_error}
        class="min-h-[calc(100*var(--pvh)-3rem)]"
      />
    </Layouts.app>
    """
  end

  attr :profiles, :list, required: true, doc: "every `Profiles.Profile`, from `ProfileAware`"
  attr :current_id, :string, default: nil, doc: "the active profile's id on a switch; nil at the door"
  attr :return_to, :string, required: true
  attr :adding?, :boolean, required: true, doc: "the name field is open in the add tile's place"
  attr :add_error, :string, default: nil
  attr :class, :string, required: true, doc: "the height the question centres in"

  defp picker(assigns) do
    assigns = assign(assigns, under_cap?: length(assigns.profiles) < Profiles.max_profiles())

    ~H"""
    <div
      class={["relative z-[1] flex flex-col items-center justify-center gap-12 px-4 py-16", @class]}
      data-page-behavior="profiles"
      data-nav-default-zone="profiles"
    >
      <h1 class="text-3xl font-semibold">Who's watching?</h1>
      <div
        id="profile-picker"
        class="flex flex-wrap items-start justify-center gap-10"
        data-nav-zone="profile_picker"
      >
        <.form
          :for={profile <- @profiles}
          for={%{}}
          id={"pick-#{profile.id}"}
          action={~p"/profiles/#{profile.id}/activate"}
          method="post"
          class="contents"
        >
          <input type="hidden" name="return_to" value={@return_to} />
          <button
            type="submit"
            class="profile-pick cursor-pointer rounded-xl p-3"
            aria-current={if profile.id == @current_id, do: "true"}
            data-nav-item
            tabindex="0"
          >
            <ProfileTile.profile_tile
              name={profile.name}
              picture_url={Profiles.picture_url(profile)}
              hue={profile.hue}
              current?={profile.id == @current_id}
            />
          </button>
        </.form>
        <button
          :if={@under_cap? and not @adding?}
          type="button"
          id="add-profile"
          class="profile-pick cursor-pointer rounded-xl p-3"
          phx-click="open_add"
          data-nav-item
          tabindex="0"
        >
          <ProfileTile.add_tile />
        </button>
        <form
          :if={@under_cap? and @adding?}
          id="add-profile-form"
          phx-submit="add_profile"
          class="flex w-36 flex-col items-center gap-3 p-3"
        >
          <%!-- The field opens in the add tile's place and takes the focus;
                it and the button row share the tile's width, so geometry
                finds them in line with a tile and Down from the field
                reaches Add and Cancel. A refusal keeps the field, and the
                text with it; a success or Cancel closes it, and the server
                never held the typed text to clear. Escape on the field is
                Cancel for the keyboard. --%>
          <.settings_input
            id="add-profile-name"
            name="name"
            autofocus
            placeholder="Name"
            maxlength={DisplayName.max_length()}
            autocomplete="off"
            class="text-center"
            phx-keydown="cancel_add"
            phx-key="Escape"
          />
          <div class="flex w-full gap-2">
            <.button
              type="submit"
              variant="neutral"
              size="sm"
              class="flex-1"
              data-nav-item
              tabindex="0"
            >
              Add
            </.button>
            <.button
              type="button"
              variant="dismiss"
              size="sm"
              class="flex-1"
              phx-click="cancel_add"
              data-nav-item
              tabindex="0"
            >
              Cancel
            </.button>
          </div>
          <p :if={@add_error} class="text-sm text-error">{@add_error}</p>
        </form>
      </div>
    </div>
    """
  end
end
