defmodule MediaCentaurWeb.Live.ProfileAware do
  @moduledoc """
  The `on_mount` hook that says who is watching (ADR-078, UIDR-053), one
  entry in `live_session :default`'s list. The active profile is the
  `"profile_id"` key of the signed session, set by `ProfileController`;
  `Logic.resolve/2` turns it and `Profiles.list/0` into the active
  profile, or `:pick`, on which the first `handle_params` redirects to
  the picker with the page's own URL as `return_to`. With one profile
  the cookie is never consulted and no picker exists.

  Assigns `:profile` (the active `Profiles.Profile`) and `:profiles`
  (every profile, for the switcher's presence and Settings → Profiles),
  subscribes to `profiles:updates` through the subscribe door, and on
  any profile event re-reads the list: a renamed active profile is
  re-assigned, a removed one drops the session to the picker. The hook
  halts those messages — no page handles them itself.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.Live.ProfileAware.Logic
  alias MediaCentaurWeb.Live.Subscriptions

  @profile_events [:profile_added, :profile_changed, :profile_removed]

  def on_mount(:default, _params, session, socket) do
    profiles = Profiles.list()

    case Logic.resolve(session["profile_id"], profiles) do
      {:active, profile} ->
        {:cont,
         socket
         |> assign(profile: profile, profiles: profiles)
         |> Subscriptions.subscribe(Profiles)
         |> attach_hook(:profile_aware, :handle_info, &on_profiles_event/2)}

      :pick ->
        {:cont, attach_hook(socket, :profile_aware_pick, :handle_params, &redirect_to_picker/3)}
    end
  end

  defp redirect_to_picker(_params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    return_to = if query, do: path <> "?" <> query, else: path
    {:halt, redirect(socket, to: "/profiles?return_to=" <> URI.encode_www_form(return_to))}
  end

  defp on_profiles_event({tag, _event}, socket) when tag in @profile_events do
    profiles = Profiles.list()

    case Enum.find(profiles, &(&1.id == socket.assigns.profile.id)) do
      nil -> {:halt, redirect(socket, to: "/profiles")}
      profile -> {:halt, assign(socket, profile: profile, profiles: profiles)}
    end
  end

  defp on_profiles_event(_message, socket), do: {:cont, socket}
end
