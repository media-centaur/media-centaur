defmodule MediaManagerWeb.PageController do
  use MediaManagerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
