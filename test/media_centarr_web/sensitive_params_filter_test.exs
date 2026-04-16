defmodule MediaCentarrWeb.SensitiveParamsFilterTest do
  @moduledoc """
  Verifies the application has Phoenix `:filter_parameters` configured to
  redact sensitive form fields from request logs. The exact list is the
  load-bearing security guarantee — adding a new sensitive key without
  updating this list silently leaks it on next form submission.

  See decisions/architecture/ for the sensitive-information policy.
  """

  use ExUnit.Case, async: true

  test "Phoenix.Logger redacts password / api_key / secret / token form params" do
    filtered =
      Phoenix.Logger.filter_values(%{
        "password" => "hunter2",
        "tmdb_api_key" => "real-tmdb-key",
        "prowlarr_api_key" => "real-prowlarr-key",
        "download_client_password" => "real-qbit-password",
        "session_token" => "session",
        "client_secret" => "shh",
        "harmless_field" => "ok"
      })

    assert filtered["password"] == "[FILTERED]"
    assert filtered["tmdb_api_key"] == "[FILTERED]"
    assert filtered["prowlarr_api_key"] == "[FILTERED]"
    assert filtered["download_client_password"] == "[FILTERED]"
    assert filtered["session_token"] == "[FILTERED]"
    assert filtered["client_secret"] == "[FILTERED]"

    # Non-sensitive values pass through.
    assert filtered["harmless_field"] == "ok"
  end
end
