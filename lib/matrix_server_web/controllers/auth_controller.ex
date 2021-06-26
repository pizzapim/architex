defmodule MatrixServerWeb.AuthController do
  use MatrixServerWeb, :controller

  import MatrixServer
  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset, only: [apply_changes: 1]

  alias MatrixServer.{Repo, Account}
  alias MatrixServerWeb.API.Register
  alias Ecto.Changeset

  @register_type "m.login.dummy"
  @login_type "m.login.password"

  def register(conn, %{"auth" => %{"type" => @register_type}} = params) do
    case Register.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input =
          apply_changes(cs)
          |> Map.from_struct()
          |> update_map_entry(:initial_device_display_name, :device_name)
          |> update_map_entry(:username, :localpart)
          |> update_map_entry(:password, :password_hash, &Bcrypt.hash_pwd_salt/1)

        case Account.register(%Account{}, input) |> Repo.transaction() do
          {:ok, %{device_with_access_token: device}} ->
            data = %{user_id: get_mxid(device.localpart)}

            data =
              if not input.inhibit_login do
                data
                |> Map.put(:device_id, device.device_id)
                |> Map.put(:access_token, device.access_token)
              else
                data
              end

            conn
            |> put_status(200)
            |> json(data)

          {:error, _, cs, _} ->
            Register.handle_error(conn, cs)
        end

      _ ->
        put_error(conn, :bad_json)
    end
  end

  def register(conn, %{"auth" => _}) do
    # Other login types are unsupported for now.
    put_error(conn, :forbidden)
  end

  def register(conn, _params) do
    # User has not started an auth flow.
    data = %{
      flows: [%{stages: [@register_type]}],
      params: %{}
    }

    conn
    |> put_status(401)
    |> json(data)
  end

  def login_types(conn, _params) do
    data = %{flows: [%{type: @login_type}]}

    conn
    |> put_status(200)
    |> json(data)
  end

  def login(conn, %{"type" => "m.login.password"}) do
    conn
    |> put_status(200)
    |> json(%{})
  end

  def login(conn, _params) do
    # Login type m.login.token is unsupported for now.
    put_error(conn, :forbidden)
  end
end
