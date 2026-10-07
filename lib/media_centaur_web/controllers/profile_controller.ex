defmodule MediaCentaurWeb.ProfileController do
  @moduledoc """
  Sets the session's active profile (ADR-078): the picker's tiles post
  here, since a LiveView cannot write a cookie. Writes `"profile_id"`
  into the signed session and returns to `return_to` under
  `ReturnTo.local_path/1`. An unknown id goes back to the picker.
  """

  use MediaCentaurWeb, :controller

  alias MediaCentaur.Profiles
  alias MediaCentaurWeb.ProfileController.ReturnTo

  # The picker route (Task 11) will make this a ~p"/profiles".
  def activate(conn, %{"id" => id} = params) do
    case Profiles.get(id) do
      nil ->
        redirect(conn, to: "/profiles")

      profile ->
        conn
        |> put_session("profile_id", profile.id)
        |> redirect(to: ReturnTo.local_path(params["return_to"]))
    end
  end
end
