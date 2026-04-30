defmodule MediaCentarrWeb.Live.CapabilitiesAware do
  @moduledoc """
  Shared `:tmdb_ready` lifecycle for any LiveView that only gates UI on
  the `Capabilities.tmdb_ready?/0` boolean (Home, Library).

  `use MediaCentarrWeb.Live.CapabilitiesAware` injects:

    * a `handle_info/2` clause for `:capabilities_changed` that re-reads
      `Capabilities.tmdb_ready?/0` and re-assigns `:tmdb_ready`
    * an `import` for `assign_tmdb_ready/1`, called once from the host
      LiveView's `mount/3` to seed the assign

  Subscribing to `MediaCentarr.Capabilities` is left to the host because
  each LiveView declares its own subscription list.

  **Don't `use` this from a LiveView whose `:capabilities_changed`
  handler does extra work or assigns more capability fields**, because
  Elixir doesn't allow two clauses with the same pattern in one module.
  In-tree, both UpcomingLive (also assigns `:acquisition_ready`) and
  AcquisitionLive (re-arms polling and may navigate away on a downgrade)
  keep their own bespoke handlers — and that's the right call. Opt
  these LiveViews out of the macro entirely; the `tmdb_ready` mount
  load is a one-liner that doesn't justify wrapping.

  Decoupling rationale: see ADR-038.
  """

  alias MediaCentarr.Capabilities

  defmacro __using__(_opts) do
    quote do
      import MediaCentarrWeb.Live.CapabilitiesAware, only: [assign_tmdb_ready: 1]

      @impl true
      def handle_info(:capabilities_changed, socket) do
        {:noreply,
         Phoenix.Component.assign(socket, :tmdb_ready, MediaCentarr.Capabilities.tmdb_ready?())}
      end
    end
  end

  @doc """
  Seeds `:tmdb_ready` from the `Capabilities` context. Call once from
  `mount/3` (after subscribing to `Capabilities` if you want live updates).
  """
  @spec assign_tmdb_ready(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_tmdb_ready(socket) do
    Phoenix.Component.assign(socket, :tmdb_ready, Capabilities.tmdb_ready?())
  end
end
