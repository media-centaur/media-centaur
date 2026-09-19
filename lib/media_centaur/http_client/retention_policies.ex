defmodule MediaCentaur.HttpClient.RetentionPolicies do
  @moduledoc """
  Retention policy owned by the HTTP layer: the request time series
  (`MediaCentaur.HttpClient.Traffic`) is a round-robin store whose own
  sweep removes rows past each resolution's retention once a minute and
  reports the count under `:request_history`.
  """
  @behaviour MediaCentaur.Retention.PolicyProvider

  alias MediaCentaur.Retention.Policy

  @impl true
  def policies do
    [
      %Policy{
        key: :request_history,
        subsystem: :http,
        label: "Request history",
        description:
          "Ten-second buckets for an hour, minute buckets for six hours, ten-minute buckets for two days, hourly buckets for 31 days; swept continuously.",
        mode: :external
      }
    ]
  end
end
