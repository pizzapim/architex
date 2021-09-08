defmodule ArchitexWeb.Client.AccountController do
  use ArchitexWeb, :controller

  import ArchitexWeb.Error

  alias Architex.{Account, Repo}
  alias Plug.Conn

  @doc """
  Checks to see if a username is available, and valid, for the server.

  Action for GET /_matrix/client/r0/register/available.
  """
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

  @doc """
  Gets information about the owner of a given access token.

  Action for GET /_matrix/client/r0/account/whoami.
  """
  def whoami(%Conn{assigns: %{account: %Account{localpart: localpart}}} = conn, _params) do
    data = %{user_id: Architex.get_mxid(localpart)}

    conn
    |> put_status(200)
    |> json(data)
  end

  @doc """
  Invalidates an existing access token, so that it can no longer be used for authorization.

  Action for POST /_matrix/client/r0/logout.
  """
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

  @doc """
  Invalidates all access tokens for a user, so that they can no longer be used
  for authorization.

  Action for POST /_matrix/client/r0/logout/all.
  """
  def logout_all(%Conn{assigns: %{account: account}} = conn, _params) do
    Repo.delete_all(Ecto.assoc(account, :devices))

    conn
    |> put_status(200)
    |> json(%{})
  end
end
