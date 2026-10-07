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
  any profile event re-reads the list and resolves the active profile
  again through `Logic.resolve/2`: a renamed one is re-assigned, a removed
  one leaves the last remaining profile active or drops the page to the
  picker, returning to it. The hook halts those messages — no page handles
  them itself.

  A page's `mount/3` must not read `:profile`: on the pick path the
  redirect happens after mount, so profile-scoped loading belongs in
  `handle_params` or `start_async`.
  """

  use MediaCentaurWeb, :verified_routes

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
         |> attach_hook(:profile_aware, :handle_info, &on_profiles_event/2)
         |> attach_hook(:profile_aware_return_to, :handle_params, &remember_return_to/3)}

      :pick ->
        {:cont, attach_hook(socket, :profile_aware_pick, :handle_params, &redirect_to_picker/3)}
    end
  end

  defp redirect_to_picker(_params, uri, socket) do
    {:halt, redirect(socket, to: ~p"/profiles?return_to=#{Logic.return_to(uri)}")}
  end

  defp remember_return_to(_params, uri, socket) do
    {:cont, assign(socket, profile_aware_return_to: Logic.return_to(uri))}
  end

  defp on_profiles_event({tag, _event}, socket) when tag in @profile_events do
    profiles = Profiles.list()

    case Logic.resolve(socket.assigns.profile.id, profiles) do
      {:active, profile} -> {:halt, assign(socket, profile: profile, profiles: profiles)}
      :pick -> {:halt, redirect(socket, to: picker_path(socket))}
    end
  end

  defp on_profiles_event(_message, socket), do: {:cont, socket}

  defp picker_path(%{assigns: %{profile_aware_return_to: return_to}}),
    do: ~p"/profiles?return_to=#{return_to}"

  defp picker_path(_socket), do: ~p"/profiles"
end
