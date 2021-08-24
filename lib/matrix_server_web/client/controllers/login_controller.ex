defmodule MatrixServerWeb.Client.LoginController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Error
  import Ecto.Changeset

  alias MatrixServer.{Repo, Account}
  alias MatrixServerWeb.Client.Request.Login
  alias Ecto.Changeset

  @login_type "m.login.password"

  @doc """
  Gets the homeserver's supported login types to authenticate users.

  Action for GET /_matrix/client/r0/login.
  """
  def login_types(conn, _params) do
    data = %{flows: [%{type: @login_type}]}

    conn
    |> put_status(200)
    |> json(data)
  end

  @doc """
  Authenticates the user, and issues an access token they can use to
  authorize themself in subsequent requests.

  Action for POST /_matrix/client/r0/login.
  """
  def login(
        conn,
        %{"type" => @login_type, "identifier" => %{"type" => "m.id.user"}} = params
      ) do
    case Login.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input = apply_changes(cs)

        case Account.login(input) |> Repo.transaction() do
          {:ok, device} ->
            data = %{
              user_id: MatrixServer.get_mxid(device.localpart),
              access_token: device.access_token,
              device_id: device.device_id
            }

            conn
            |> put_status(200)
            |> json(data)

          {:error, error} when is_atom(error) ->
            put_error(conn, error)

          {:error, _} ->
            put_error(conn, :unknown)
        end

      _ ->
        put_error(conn, :bad_json)
    end
  end

  def login(conn, _params) do
    # Other login types and identifiers are unsupported for now.
    put_error(conn, :unrecognized, "Only m.login.password is supported currently.")
  end
end
