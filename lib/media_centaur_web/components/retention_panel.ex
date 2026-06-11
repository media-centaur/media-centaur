defmodule MediaCentaurWeb.RetentionPanel do
  @moduledoc """
  The "Data retention" section of a subsystem drill-in on the Status page.

  Lists each `MediaCentaur.Retention.PolicyStatus` routed to the subsystem:
  the human-readable policy ("what is kept, for how long") plus the
  observed pruning behavior ("swept 3h ago · 12 removed"). Policies that
  keep data forever render their declaration too — permanence is a
  decision the page should state, not an absence.
  """
  use Phoenix.Component

  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]

  alias MediaCentaur.Retention.PolicyStatus

  @doc """
  Renders one subsystem's retention policies as a quiet inset list.
  Neutral text throughout — retention is plumbing, not a health signal.
  """
  attr :policies, :list, required: true, doc: "[Retention.PolicyStatus.t()] for one subsystem"

  def retention_panel(assigns) do
    ~H"""
    <div class="space-y-2">
      <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
        Data retention
      </h3>
      <div class="glass-inset rounded-lg divide-y divide-base-content/5">
        <div :for={policy <- @policies} id={"retention-#{policy.key}"} class="px-3 py-2 space-y-0.5">
          <div class="flex items-baseline justify-between gap-3">
            <span class="text-sm text-base-content/80">{policy.label}</span>
            <span class="text-xs text-base-content/45 whitespace-nowrap">
              {sweep_summary(policy)}
            </span>
          </div>
          <p class="text-xs text-base-content/55 leading-relaxed">
            {policy.description}
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The right-aligned one-liner summarising a policy's observed pruning
  behavior. Sweep policies read "swept", external pruners read "pruned"
  (their cadence is their own), and `:forever` policies state the
  decision.
  """
  @spec sweep_summary(PolicyStatus.t()) :: String.t()
  def sweep_summary(%PolicyStatus{mode: :forever}), do: "kept forever"
  def sweep_summary(%PolicyStatus{mode: :sweep, last_ran_at: nil}), do: "not swept yet"
  def sweep_summary(%PolicyStatus{mode: :external, last_ran_at: nil}), do: "continuous"

  def sweep_summary(%PolicyStatus{mode: mode} = status) do
    verb = if mode == :sweep, do: "swept", else: "pruned"

    "#{verb} #{time_ago(status.last_ran_at)} · #{status.pruned_last_run} removed " <>
      "(#{status.pruned_total} all-time)"
  end
end
