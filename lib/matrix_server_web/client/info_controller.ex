defmodule MatrixServerWeb.Client.InfoController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error

  @supported_versions ["r0.6.1"]

  def versions(conn, _params) do
    data = %{versions: @supported_versions}

    conn
    |> put_status(200)
    |> json(data)
  end

  def unrecognized(conn, _params) do
    put_error(conn, :unrecognized)
  end
end
