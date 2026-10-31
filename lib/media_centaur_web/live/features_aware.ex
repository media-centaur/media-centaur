defmodule MediaCentaurWeb.Live.FeaturesAware do
  @moduledoc """
  The one `on_mount` that tells every LiveView which features are on
  (`MediaCentaur.Features`, ADR-081), and owns the way a page turns one on.

  Registered session-wide in the router's default `live_session`, so the
  shell can draw the sidebar on every page and a gated page can read its
  own flag, without any LiveView opting in. Three responsibilities:

    * assigns `:features`, the `MapSet` of enabled feature ids
      (`Features.enabled/0`, one Settings read), and re-assigns it when a
      `{:setting_changed, "feature:<id>", _}` broadcast arrives — the
      subscription goes through the one door (`Live.Subscriptions`), shared
      with every other settings-aware trait on the socket;
    * keeps `:page_path`, the path and query the socket is on, from a
      `handle_params` hook;
    * answers the `"turn_on_feature"` event the off state's button pushes
      (`Components.FeatureOff`): sets the flag and navigates to the same
      path, so the page mounts again with the feature on and its loads run.

  A gated LiveView reads `id in socket.assigns.features` in `handle_params`
  to skip its loads while off, and `:if={id in @features}` in its template
  to draw the off state instead of its content. The sidebar does the same
  per entry; `Layouts.app` takes the set as its `features` attr.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4, push_navigate: 2]

  alias MediaCentaur.Features
  alias MediaCentaur.Settings
  alias MediaCentaurWeb.Live.Subscriptions

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> assign(features: Features.enabled(), page_path: "/")
      |> Subscriptions.subscribe(Settings)
      |> attach_hook(:features_aware_info, :handle_info, &on_info/2)
      |> attach_hook(:features_aware_params, :handle_params, &on_params/3)
      |> attach_hook(:features_aware_event, :handle_event, &on_event/3)

    {:cont, socket}
  end

  defp on_info({:setting_changed, key, _value}, socket) do
    if Features.feature_key?(key),
      do: {:cont, assign(socket, features: Features.enabled())},
      else: {:cont, socket}
  end

  defp on_info(_message, socket), do: {:cont, socket}

  defp on_params(_params, uri, socket) do
    %URI{path: path, query: query} = URI.parse(uri)
    {:cont, assign(socket, page_path: if(query, do: "#{path}?#{query}", else: path))}
  end

  defp on_event("turn_on_feature", %{"feature" => id}, socket) do
    case Features.find(id) do
      nil ->
        {:halt, socket}

      feature ->
        Features.set(feature.id, true)
        {:halt, push_navigate(socket, to: socket.assigns.page_path)}
    end
  end

  defp on_event(_event, _params, socket), do: {:cont, socket}
end
