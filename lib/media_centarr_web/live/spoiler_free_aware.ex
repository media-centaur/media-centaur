defmodule MediaCentarrWeb.Live.SpoilerFreeAware do
  @moduledoc """
  Shared `:spoiler_free` lifecycle for any LiveView that hides spoilery
  detail when the setting is on (Home, Library, Settings).

  `use MediaCentarrWeb.Live.SpoilerFreeAware` injects:

    * a `handle_info/2` clause for `{:setting_changed, "spoiler_free_mode", enabled}`
      that re-assigns `:spoiler_free`
    * an `import` for `assign_spoiler_free/1`, called once from the host
      LiveView's `mount/3` to seed the assign

  Subscribing to `MediaCentarr.Settings` is left to the host because each
  LiveView already has its own subscription list and may listen for
  several setting keys for unrelated reasons.

  Decoupling rationale: see ADR-038. Before this module existed, three
  LiveViews each privately defined `load_spoiler_free_setting/0`,
  assigned it in mount, and pattern-matched the same PubSub message —
  exactly the duplication the second-copy rule prohibits.
  """

  alias MediaCentarr.Settings

  @setting_key "spoiler_free_mode"

  defmacro __using__(_opts) do
    quote do
      import MediaCentarrWeb.Live.SpoilerFreeAware, only: [assign_spoiler_free: 1]

      @impl true
      def handle_info({:setting_changed, unquote(@setting_key), enabled}, socket) do
        {:noreply, Phoenix.Component.assign(socket, :spoiler_free, enabled == true)}
      end
    end
  end

  @doc """
  Seeds `:spoiler_free` from the `Settings` context. Call once from
  `mount/3` (after subscribing to `Settings` if you want live updates).
  """
  @spec assign_spoiler_free(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_spoiler_free(socket) do
    Phoenix.Component.assign(socket, :spoiler_free, current_value())
  end

  defp current_value do
    case Settings.get_by_key(@setting_key) do
      {:ok, %{value: %{"enabled" => enabled}}} -> enabled == true
      _ -> false
    end
  end
end
