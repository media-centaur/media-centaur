defmodule MediaCentaurWeb.Api.PursuitJSONTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitStatus}
  alias MediaCentaurWeb.Api.PursuitJSON

  test "each available action is named for the API request that takes it" do
    status = %PursuitStatus{
      pursuit_id: Ecto.UUID.generate(),
      pursuit: %{title: "Sample Movie"},
      state: :active,
      origin: :manual,
      current_action: %CurrentAction{verb: "Stalled", description: "No peers.", severity: :warning},
      available_actions: [:cancel, :request_decision],
      staleness: :fresh,
      units: [],
      targets: %{}
    }

    assert %{available_actions: [:cancel, :choose_release]} = PursuitJSON.detail(status)
  end
end
