defmodule MediaCentaur.HttpClient.RetentionPoliciesTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.HttpClient.RetentionPolicies
  alias MediaCentaur.Retention.Policy

  test "declares the request-history policy on the Connections subsystem" do
    assert [%Policy{key: :request_history, subsystem: :http, mode: :external, run: nil}] =
             RetentionPolicies.policies()
  end
end
