defmodule MatrixServerWeb.AuthController do
  use MatrixServerWeb, :controller

  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset

  alias MatrixServer.{Repo, Account}
  alias MatrixServerWeb.API.{Register, Login}
  alias Ecto.Changeset

  @register_type "m.login.dummy"
  @login_type "m.login.password"

  def register(conn, %{"auth" => %{"type" => @register_type}} = params) do
    case Register.changeset(params) do
      %Changeset{valid?: true} = cs ->
        # TODO: refactor this
        input =
          apply_changes(cs)
          |> Map.from_struct()
          |> MatrixServer.maybe_update_map(:initial_device_display_name, :display_name)
          |> MatrixServer.maybe_update_map(:username, :localpart)
          |> MatrixServer.maybe_update_map(:password, :password_hash, &Bcrypt.hash_pwd_salt/1)

        case Account.register(input) |> Repo.transaction() do
          {:ok, %{device_with_access_token: device}} ->
            data = %{user_id: MatrixServer.get_mxid(device.localpart)}

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
            IO.inspect(cs)
            put_error(conn, Register.get_error(cs))
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

  def login(
        conn,
        %{"type" => @login_type, "identifier" => %{"type" => "m.id.user"}} = params
      ) do
    case Login.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input =
          apply_changes(cs)
          |> Map.from_struct()
          |> MatrixServer.maybe_update_map(:initial_device_display_name, :display_name)
          |> MatrixServer.maybe_update_map(:identifier, :localpart, fn
            %{user: "@" <> rest} ->
              case String.split(rest) do
                [localpart, _] -> localpart
                # Empty string will never match in the database.
                _ -> ""
              end

            %{user: user} ->
              user
          end)

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

          {:error, error} ->
            put_error(conn, error)
        end

      _ ->
        put_error(conn, :bad_json)
    end
  end

  def login(conn, _params) do
    # Other login types and identifiers are unsupported for now.
    put_error(conn, :unknown)
  end
end
