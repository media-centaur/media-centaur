defmodule MediaCentaur.Retention.PolicyProvider do
  @moduledoc """
  Behaviour for context-owned retention-policy declarations.

  Each bounded context that retains prunable data ships a provider module
  (e.g. `MediaCentaur.ErrorReports.RetentionPolicies`) returning its
  `MediaCentaur.Retention.Policy` structs. Providers are registered in
  config under `:retention_policy_providers` and resolved by
  `MediaCentaur.Retention` at runtime — the same boundary-clean IoC shape
  as the ErrorReports subsystem contributors — so contexts may depend on
  `Retention` (to record run stats) without creating a cycle.
  """

  @callback policies() :: [MediaCentaur.Retention.Policy.t()]
end
