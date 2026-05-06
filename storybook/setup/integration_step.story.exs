defmodule MediaCentarrWeb.Storybook.Setup.IntegrationStep do
  @moduledoc """
  One step in the Setup Tour for a network integration (TMDB, Prowlarr,
  download client). The form fields slot is provided by the parent
  LiveView and varies per integration; the variations here use plain
  inputs to demonstrate the chrome.

  ## Contract shape

      attr :result, MediaCentarrWeb.Live.SetupLive.Probe.Result, required: true
      attr :title, :string, required: true
      attr :step_index, :integer, required: true
      attr :total_steps, :integer, required: true
      slot :form, required: true
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentarrWeb.Live.SetupLive.Probe

  def function, do: &MediaCentarrWeb.Components.SetupSteps.integration_step/1
  def render_source, do: :function
  def layout, do: :one_column

  def variations do
    [
      %Variation{
        id: :tmdb_not_configured,
        description: "TMDB step on first visit — no key entered yet.",
        attributes: %{
          title: "TMDB (metadata)",
          step_index: 2,
          total_steps: 6,
          result: %Probe.Result{
            id: :tmdb,
            status: :not_configured,
            detail: "Without TMDB, no metadata will be fetched.",
            critical?: true
          }
        },
        slots: [
          """
          <:form>
            <label class="text-xs uppercase tracking-wide opacity-60">API key</label>
            <input
              type="password"
              placeholder="paste your TMDB v4 read-access token"
              class="input input-bordered w-full font-mono text-sm"
            />
          </:form>
          """
        ]
      },
      %Variation{
        id: :tmdb_connected,
        description: "TMDB key configured and verified.",
        attributes: %{
          title: "TMDB (metadata)",
          step_index: 2,
          total_steps: 6,
          result: %Probe.Result{
            id: :tmdb,
            status: :ok,
            detail: "Connection verified.",
            critical?: true
          }
        },
        slots: [
          """
          <:form>
            <label class="text-xs uppercase tracking-wide opacity-60">API key</label>
            <input
              type="password"
              value="••••••••••••••••"
              class="input input-bordered w-full font-mono text-sm"
            />
          </:form>
          """
        ]
      },
      %Variation{
        id: :prowlarr_auth_failed,
        description: "Prowlarr URL set but key rejected.",
        attributes: %{
          title: "Prowlarr (indexer)",
          step_index: 5,
          total_steps: 6,
          result: %Probe.Result{
            id: :prowlarr,
            status: :error,
            detail: "Connection failed: 401 Unauthorized.",
            critical?: false
          }
        },
        slots: [
          """
          <:form>
            <label class="text-xs uppercase tracking-wide opacity-60">URL</label>
            <input
              type="text"
              value="http://localhost:9696"
              class="input input-bordered w-full font-mono text-sm"
            />
            <label class="text-xs uppercase tracking-wide opacity-60 mt-2 block">API key</label>
            <input
              type="password"
              value="••••••••••••"
              class="input input-bordered w-full font-mono text-sm"
            />
          </:form>
          """
        ]
      },
      %Variation{
        id: :download_client_skipped,
        description: "Download client step — fully optional, easy to skip.",
        attributes: %{
          title: "Download client",
          step_index: 6,
          total_steps: 6,
          result: %Probe.Result{
            id: :download_client,
            status: :not_configured,
            detail: "Optional — needed to track download progress.",
            critical?: false
          }
        },
        slots: [
          """
          <:form>
            <p class="text-sm opacity-70">
              Configure later in Settings if you want grab-progress tracking.
            </p>
          </:form>
          """
        ]
      }
    ]
  end
end
