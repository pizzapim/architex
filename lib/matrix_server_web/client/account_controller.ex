defmodule MatrixServerWeb.Client.AccountController do
  use MatrixServerWeb, :controller

  import MatrixServer
  import MatrixServerWeb.Plug.Error

  alias MatrixServer.{Account, Repo}
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

  def logout(%Conn{assigns: %{device: device}} = conn, _params) do
    case Repo.delete(device) do
      {:ok, _} ->
        conn
        |> put_status(200)
        |> json(%{})

      {:error, _} ->
        put_error(conn, :unknown)
    end
  end

  def logout_all(%Conn{assigns: %{account: account}} = conn, _params) do
    Repo.delete_all(Ecto.assoc(account, :devices))

    conn
    |> put_status(200)
    |> json(%{})
  end
end
