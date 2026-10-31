defmodule MediaCentaurWeb.DiscoveryLive do
  @moduledoc """
  The Discovery page: movies that recently became available digitally,
  from TMDB (campaign `discovery.md`). A feature in development
  (ADR-081): off by default, its sidebar entry and this page exist while
  the `:discovery` flag is on, and the page is its off state otherwise.

  Iteration-phase: the page is empty until the campaign's design
  milestones say what fills it, so it carries no nav zones yet; the
  hardening pass gives it its input wiring.
  """
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.Features
  alias MediaCentaurWeb.Components.FeatureOff

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Discovery")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      profile={@profile}
      profiles={@profiles}
      viewing_layer={assigns[:viewing_layer]}
      features={@features}
      flash={@flash}
      current_path="/discovery"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <FeatureOff.feature_off
        :if={:discovery not in @features}
        id="discovery-off"
        feature={Features.get(:discovery)}
      />
      <div :if={:discovery in @features} class="relative">
        <.page_header title="Discovery" />
        <.empty_state
          id="discovery-empty"
          icon="hero-sparkles"
          headline="Recent digital releases will land here"
        >
          Discovery is in development. It will show movies that recently became available to stream, rent or buy, from TMDB.
        </.empty_state>
      </div>
    </Layouts.app>
    """
  end
end
