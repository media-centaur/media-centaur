defmodule MediaCentaur.ProwlarrStubs do
  use Boundary, top_level?: true, check: [in: false, out: false]

  @moduledoc """
  Shared Prowlarr readiness helper (mirrors `DownloadClientStubs`).

  `mark_ready!/0` makes `MediaCentaur.Capabilities.prowlarr_ready?/0`
  true. Readiness has two halves and a test that reaches the Prowlarr
  client needs both: a URL and API key in the `Settings.Config`
  `:persistent_term` snapshot, and a recorded passing connection test.
  Configuring only the URL leaves `prowlarr_ready?/0` false, which the
  acquisition worker reads as "not configured" and refuses to search.

  Requires a sync test (`MediaCentaur.DataCase`, or `MediaCentaur.Case,
  async: false`): the sandbox restores the config `:persistent_term` at
  check-in and the SQL sandbox rolls back the stored test result, so
  callers clean up nothing.
  """

  alias MediaCentaur.Capabilities
  alias MediaCentaur.Secret
  alias MediaCentaur.Settings.Config

  @doc "Configures Prowlarr and records a passing connection test."
  @spec mark_ready!() :: :ok
  def mark_ready! do
    config = :persistent_term.get({Config, :config})

    :persistent_term.put(
      {Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, Secret.wrap("test-key"))
    )

    %{status: :ok} = Capabilities.save_test_result(:prowlarr, :ok)
    true = Capabilities.prowlarr_ready?()

    :ok
  end
end
