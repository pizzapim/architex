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
        api = apply_changes(cs)

        case Account.register(api) |> Repo.transaction() do
          {:ok, %{device_with_access_token: device}} ->
            data = %{user_id: MatrixServer.get_mxid(device.localpart)}

            data =
              if not api.inhibit_login do
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
        api = apply_changes(cs)
        # input =
        #   apply_changes(cs)
        #   |> Map.from_struct()
        #   |> MatrixServer.maybe_update_map(:initial_device_display_name, :display_name)

        case Account.login(api) |> Repo.transaction() do
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
