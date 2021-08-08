defmodule MatrixServerWeb.Federation.TestController do
  use MatrixServerWeb, :controller
  use MatrixServerWeb.AuthenticateServer

  def test(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{})
  end
end
