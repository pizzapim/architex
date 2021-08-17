defmodule MatrixServerWeb.Federation.EventController do
  use MatrixServerWeb, :controller
  use MatrixServerWeb.Federation.AuthenticateServer

  def event(conn, %{"event_id" => event_id}) do

  end
end
