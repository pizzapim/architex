defmodule MatrixServerWeb.AuthController do
  use MatrixServerWeb, :controller

  import MatrixServer
  import MatrixServerWeb.Plug.Error
  import Ecto.Changeset, only: [apply_changes: 1]
  import Ecto.Query

  alias MatrixServer.{Repo, Account, Device}
  alias MatrixServerWeb.API.{Register, Login}
  alias Ecto.Changeset

  @register_type "m.login.dummy"
  @login_type "m.login.password"

  def register(conn, %{"auth" => %{"type" => @register_type}} = params) do
    case Register.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input =
          apply_changes(cs)
          |> Map.from_struct()
          |> update_map_entry(:initial_device_display_name, :display_name)
          |> update_map_entry(:username, :localpart)
          |> update_map_entry(:password, :password_hash, &Bcrypt.hash_pwd_salt/1)

        case Account.register(input) |> Repo.transaction() do
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

  def login(
        conn,
        %{"type" => @login_type, "identifier" => %{"type" => "m.id.user"}} = params
      ) do
    case Login.changeset(params) do
      %Changeset{valid?: true} = cs ->
        input =
          apply_changes(cs)
          |> Map.from_struct()
          |> update_map_entry(:initial_device_display_name, :display_name)
          |> update_map_entry(:identifier, :localpart, fn
            %{user: "@" <> rest} ->
              case String.split(rest) do
                [localpart, _] -> localpart
                # Empty string will never match in the database.
                _ -> ""
              end

            %{user: user} ->
              user
          end)

        case Repo.transaction(login_transaction(input)) do
          {:ok, device} ->
            data = %{
              user_id: get_mxid(device.localpart),
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

  defp login_transaction(%{localpart: localpart, password: password} = params) do
    fn repo ->
      case repo.one(from a in Account, where: a.localpart == ^localpart) do
        %Account{password_hash: hash} = account ->
          if Bcrypt.verify_pass(password, hash) do
            device_id = Map.get(params, :device_id, Device.generate_device_id(localpart))
            access_token = Device.generate_access_token(localpart, device_id)

            update_query =
              from(d in Device)
              |> update(set: [access_token: ^access_token, device_id: ^device_id])

            update_query =
              if params[:display_name] != nil do
                update(update_query, set: [display_name: ^params.display_name])
              else
                update_query
              end

            result =
              Ecto.build_assoc(account, :devices)
              |> Map.put(:device_id, device_id)
              |> Map.put(:access_token, access_token)
              |> Device.changeset(params)
              |> repo.insert(on_conflict: update_query, conflict_target: [:localpart, :device_id])

            case result do
              {:ok, device} ->
                device

              {:error, _cs} ->
                repo.rollback(:forbidden)
            end
          else
            repo.rollback(:forbidden)
          end

        nil ->
          repo.rollback(:forbidden)
      end
    end
  end
end
