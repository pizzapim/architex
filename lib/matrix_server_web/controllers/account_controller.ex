defmodule MatrixServerWeb.AccountController do
  use MatrixServerWeb, :controller

  import MatrixServer
  import MatrixServerWeb.Plug.Error

  alias MatrixServer.Account
  alias Plug.Conn

  def available(conn, params) do
    localpart = Map.get(params, "username", "")

    case Account.available?(localpart) do
      :ok ->
        conn
        |> put_status(200)
        |> json(%{available: true})

      {:error, error} ->
        put_error(conn, error)
    end
  end

  def whoami(%Conn{assigns: %{account: %Account{localpart: localpart}}} = conn, _params) do
    data = %{user_id: get_mxid(localpart)}

    conn
    |> put_status(200)
    |> json(data)
  end
end
