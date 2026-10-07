defmodule MediaCentaurWeb.ProfilesLive do
  @moduledoc """
  The picker at `/profiles` (UIDR-053): "Who's watching?" over a tile
  per profile and, under the cap, an inline Add. A tile is a plain form
  posting to `ProfileController.activate/2` with `return_to`, since the
  session cookie is the controller's to write; the input system
  activates its button like any other on SELECT. Sidebar-less, in its
  own `live_session :profiles` so `ProfileAware` does not run here.
  Subscribes to `profiles:updates` so a profile added from Settings
  shows at once.
  """

  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.Components.Settings, only: [settings_input: 1]

  alias MediaCentaur.DisplayName
  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Components.ProfileTile
  alias MediaCentaurWeb.Live.Subscriptions
  alias MediaCentaurWeb.ProfileController.ReturnTo
  alias MediaCentaurWeb.ProfileWords

  @profile_events [:profile_added, :profile_changed, :profile_removed]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Who's watching?", profiles: [], return_to: "/", add_error: nil, added: 0)
     |> Subscriptions.subscribe(Profiles)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket, profiles: Profiles.list(), return_to: ReturnTo.local_path(params["return_to"]))}
  end

  @impl true
  def handle_event("add_profile", %{"name" => name}, socket) do
    case Profiles.add(name) do
      {:ok, _profile} -> {:noreply, assign(socket, added: socket.assigns.added + 1, add_error: nil)}
      {:error, reason} -> {:noreply, assign(socket, add_error: ProfileWords.error(reason))}
    end
  end

  @impl true
  def handle_info({tag, _event}, socket) when tag in @profile_events,
    do: {:noreply, assign(socket, profiles: Profiles.list())}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.input_system_root class="relative min-h-viewport">
      <div class="page-side-dim page-side-dim-calm" aria-hidden="true"></div>
      <div
        class="relative z-[1] flex min-h-viewport flex-col items-center justify-center gap-12 px-4 py-16"
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
    </Layouts.input_system_root>
    """
  end
end
