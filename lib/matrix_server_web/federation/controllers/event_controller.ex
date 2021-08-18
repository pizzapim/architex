defmodule MatrixServerWeb.Federation.EventController do
  use MatrixServerWeb, :controller
  use MatrixServerWeb.Federation.AuthenticateServer

  def event(conn, %{"event_id" => _event_id}) do
    conn
    |> put_status(200)
    |> json(%{})
  end
end
