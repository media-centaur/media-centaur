defmodule MediaCentaurWeb.ProfilesLive do
  @moduledoc """
  The picker at `/profiles` (UIDR-053): "Who's watching?" over a tile
  per profile and, under the cap, an inline Add. A tile is a plain form
  posting to `ProfileController.activate/2` with `return_to`, since the
  session cookie is the controller's to write; the input system
  activates its button like any other on SELECT.

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
    {:ok, assign(socket, page_title: "Who's watching?", return_to: "/", add_error: nil, added: 0)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, return_to: ReturnTo.local_path(params["return_to"]))}
  end

  @impl true
  def handle_event("add_profile", %{"name" => name}, socket) do
    case Profiles.add(name) do
      {:ok, _profile} -> {:noreply, assign(socket, added: socket.assigns.added + 1, add_error: nil)}
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
        added={@added}
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
        return_to={@return_to}
        added={@added}
        add_error={@add_error}
        class="min-h-[calc(100*var(--pvh)-3rem)]"
      />
    </Layouts.app>
    """
  end

  attr :profiles, :list, required: true, doc: "every `Profiles.Profile`, from `ProfileAware`"
  attr :return_to, :string, required: true
  attr :added, :integer, required: true
  attr :add_error, :string, default: nil
  attr :class, :string, required: true, doc: "the height the question centres in"

  defp picker(assigns) do
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
            class="cursor-pointer rounded-xl p-3"
            data-nav-item
            tabindex="0"
          >
            <ProfileTile.profile_tile
              name={profile.name}
              picture_url={Profiles.picture_url(profile)}
              hue={profile.hue}
            />
          </button>
        </.form>
        <form
          :if={length(@profiles) < Profiles.max_profiles()}
          id="add-profile-form"
          phx-submit="add_profile"
          class="flex w-36 flex-col items-center gap-3 p-3"
        >
          <%!-- The field and its button share one width, so geometry finds
                them equally in line with a tile and document order sends
                Right from a tile to the field; Down from the field reaches
                the button. The field's id counts the adds: a success
                replaces it with an empty field that takes the focus, since
                the server never held the typed text to clear. A refusal
                keeps it, and the text with it. --%>
          <.settings_input
            id={"add-profile-name-#{@added}"}
            name="name"
            autofocus={@added > 0}
            placeholder="Add profile"
            maxlength={DisplayName.max_length()}
            autocomplete="off"
            class="text-center"
          />
          <.button
            type="submit"
            variant="neutral"
            size="sm"
            class="w-full"
            data-nav-item
            tabindex="0"
          >
            Add
          </.button>
          <p :if={@add_error} class="text-sm text-error">{@add_error}</p>
        </form>
      </div>
    </div>
    """
  end
end
