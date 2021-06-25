defmodule MatrixServerWeb.AccountController do
  use MatrixServerWeb, :controller

  import MatrixServer, only: [get_mxid: 1]

  alias MatrixServer.Account
  alias Plug.Conn

  def available(conn, params) do
    localpart = Map.get(params, "username", "")

    {status, data} =
      case Account.available?(localpart) do
        :ok ->
          {200, %{available: true}}

        {:error, :user_in_use} ->
          {400, %{errcode: "M_USER_IN_USE", error: "Desired user ID is already taken."}}

        {:error, :invalid_username} ->
          {400, %{errocode: "M_INVALID_USERNAME", error: "Desired user ID is invalid."}}
      end

    conn
    |> put_status(status)
    |> json(data)
  end

  def whoami(%Conn{assigns: %{account: %Account{localpart: localpart}}} = conn, _params) do
    data = %{user_id: get_mxid(localpart)}

    conn
    |> put_status(200)
    |> json(data)
  end
end
