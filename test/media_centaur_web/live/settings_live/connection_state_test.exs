defmodule MediaCentaurWeb.SettingsLive.ConnectionStateTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.IntegrationHealth.Status
  alias MediaCentaurWeb.SettingsLive.ConnectionState

  @tested ~U[2026-09-13 10:00:00Z]

  defp status(id, configured?, test_state, opts \\ []) do
    %Status{
      id: id,
      configured?: configured?,
      test_state: test_state,
      last_tested_at: opts[:tested_at]
    }
  end

  test "not configured" do
    row = ConnectionState.build(status(:prowlarr, false, :unknown), %{}, nil)

    assert %ConnectionState{
             id: :prowlarr,
             state: :not_configured,
             state_label: "Not configured",
             address: nil,
             tested_at: nil
           } = row
  end

  test "configured, not tested" do
    config = %{prowlarr_url: "http://localhost:9696", prowlarr_api_key_configured?: true}
    row = ConnectionState.build(status(:prowlarr, true, :unknown), config, nil)

    assert %ConnectionState{
             state: :not_tested,
             state_label: "Not tested",
             address: "http://localhost:9696",
             credential: "API key set"
           } = row
  end

  test "pending, ok and error follow the owner's test_state and words" do
    assert %{state: :pending, state_label: "Testing…"} =
             ConnectionState.build(status(:tmdb, true, :pending), %{}, nil)

    assert %{state: :ok, state_label: "Connected", tested_at: @tested} =
             ConnectionState.build(status(:prowlarr, true, :ok, tested_at: @tested), %{}, nil)

    assert %{state: :error, state_label: "Unreachable"} =
             ConnectionState.build(status(:prowlarr, true, :error), %{}, nil)

    assert %{state_label: "Unreachable or auth failed"} =
             ConnectionState.build(status(:download_client, true, :error), %{}, nil)

    assert %{state_label: "Unreachable or bad API key"} =
             ConnectionState.build(status(:usenet_download_client, true, :error), %{}, nil)
  end

  test "the age is only shown for a result" do
    assert %{tested_at: nil} =
             ConnectionState.build(status(:tmdb, true, :pending, tested_at: @tested), %{}, nil)
  end

  test "a pending detection overrides the state and prefills the form" do
    detected = %{type: "qbittorrent", url: "http://qbittorrent:8080", username: "admin"}
    row = ConnectionState.build(status(:download_client, false, :unknown), %{}, detected)

    assert %{
             state: :detected,
             state_label: "Detected from Prowlarr, not saved",
             address: "http://qbittorrent:8080",
             prefill: ^detected
           } = row
  end

  test "credential summary names what is stored, never the value" do
    build = &ConnectionState.build(status(&1, true, :unknown), &2, nil).credential

    assert build.(:tmdb, %{tmdb_api_key_configured?: true}) == "API key set"
    assert build.(:prowlarr, %{prowlarr_api_key_configured?: false}) == nil

    assert build.(:download_client, %{
             download_client_username: "admin",
             download_client_password_configured?: true
           }) == "admin · password set"

    assert build.(:download_client, %{
             download_client_username: nil,
             download_client_password_configured?: true
           }) == "password set"

    assert build.(:usenet_download_client, %{usenet_download_client_api_key_configured?: true}) ==
             "API key set"
  end
end
