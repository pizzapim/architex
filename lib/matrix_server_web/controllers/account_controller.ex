defmodule MatrixServerWeb.AccountController do
  use MatrixServerWeb, :controller
  alias MatrixServer.Account

  def register(conn, _params) do
    conn
  end

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
end
