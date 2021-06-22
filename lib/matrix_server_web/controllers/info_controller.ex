defmodule MatrixServerWeb.InfoController do
  use MatrixServerWeb, :controller

  @supported_versions ["r0.6.1"]

  def versions(conn, _params) do
    data = %{versions: @supported_versions}

    conn
    |> put_status(200)
    |> json(data)
  end
end
